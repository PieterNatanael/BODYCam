import StoreKit
import Foundation

// MARK: - SKProduct price helper

extension SKProduct {
    var localizedPrice: String? {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = priceLocale
        return f.string(from: price)
    }
}

// MARK: - SubscriptionManager

final class SubscriptionManager: NSObject, ObservableObject {

    // MARK: - Config

    static let productIDs: Set<String> = [
        "com.lb.pro.weekly",
        "com.lb.pro.monthly",
        "com.lb.pro.yearly"
    ]

    /// Calendar date of the freemium launch (UTC midnight, April 18 2026).
    /// Anyone whose receipt shows original_purchase_date before this date bought the paid app.
    private static let grandfatherCutoff: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 18
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // MARK: - Debug

    /// Set true in Xcode to simulate a brand-new free user (ignores receipt + cache).
    /// MUST be false before submitting to App Store.
    #if DEBUG
    static var simulateFreeUser = false
    #endif

    /// Set true in Xcode to simulate an unlocked (paid/grandfathered) user —
    /// useful in Simulator, where real StoreKit purchases aren't available.
    /// Takes priority over `simulateFreeUser` if both are somehow true.
    /// MUST be false before submitting to App Store.
    #if DEBUG
    static var simulateUnlockedUser = false
    #endif

    // MARK: - Published state

    @Published var isSubscribed    = false
    @Published var isGrandfathered = false
    @Published var products: [SKProduct] = []
    // Preferred default selection, and the fallback order used to correct it
    // if the preferred product isn't actually configured in App Store
    // Connect — see reconcileSelectedProduct().
    private static let preferredProductOrder = [
        "com.lb.pro.monthly", "com.lb.pro.yearly", "com.lb.pro.weekly"
    ]
    @Published var selectedProductID: String = SubscriptionManager.preferredProductOrder[0]
    @Published var isLoading       = false
    @Published var errorMessage: String?

    /// Products sorted weekly → monthly → yearly.
    var sortedProducts: [SKProduct] {
        let order = ["com.lb.pro.weekly", "com.lb.pro.monthly", "com.lb.pro.yearly"]
        return products.sorted {
            (order.firstIndex(of: $0.productIdentifier) ?? 99) <
            (order.firstIndex(of: $1.productIdentifier) ?? 99)
        }
    }

    /// The currently selected product (nil while still loading).
    var selectedProduct: SKProduct? {
        products.first { $0.productIdentifier == selectedProductID }
    }

    /// True when the user should have full access.
    var isUnlocked: Bool {
        #if DEBUG
        if Self.simulateUnlockedUser { return true }
        if Self.simulateFreeUser { return false }
        #endif
        return isSubscribed || isGrandfathered
    }

    // MARK: - Private

    private let expiryKey = "bodycam_sub_expiry"
    private var receiptRefreshRequest: SKReceiptRefreshRequest?

    // MARK: - Lifecycle

    /// Call once from RootView.onAppear.
    func start() {
        SKPaymentQueue.default().add(self)
        loadCachedSubscription()
        checkGrandfatheredStatus()
        fetchProducts()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    // MARK: - Grandfather check (fully local, no server)

    private func checkGrandfatheredStatus() {
        guard let url = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            // No receipt on device — request a refresh (common on first run / simulator)
            refreshReceipt()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = ReceiptReader.isGrandfathered(
                receiptData: data,
                cutoffDate: Self.grandfatherCutoff
            )
            DispatchQueue.main.async { self.isGrandfathered = result }
        }
    }

    private func refreshReceipt() {
        let req = SKReceiptRefreshRequest()
        req.delegate = self
        req.start()
        receiptRefreshRequest = req
    }

    // MARK: - Subscription cache

    private func loadCachedSubscription() {
        let expiry = UserDefaults.standard.double(forKey: expiryKey)
        isSubscribed = expiry > 0 && Date().timeIntervalSince1970 < expiry
    }

    /// Cache the subscription with a per-period duration.
    private func markSubscribed(productID: String) {
        let seconds: Double
        switch productID {
        case "com.lb.pro.weekly":  seconds = 7  * 24 * 3600
        case "com.lb.pro.monthly": seconds = 31 * 24 * 3600
        default:                   seconds = 366 * 24 * 3600  // yearly
        }
        let expiry = Date().timeIntervalSince1970 + seconds
        UserDefaults.standard.set(expiry, forKey: expiryKey)
        isSubscribed = true
    }

    // MARK: - Product fetch

    func fetchProducts() {
        let req = SKProductsRequest(productIdentifiers: Self.productIDs)
        req.delegate = self
        req.start()
    }

    // MARK: - Purchase / Restore

    func purchase() {
        guard let product = selectedProduct else {
            errorMessage = "Product not available. Check your connection and try again."
            return
        }
        guard SKPaymentQueue.canMakePayments() else {
            errorMessage = "Purchases are disabled on this device."
            return
        }
        isLoading = true
        errorMessage = nil
        SKPaymentQueue.default().add(SKPayment(product: product))
    }

    func restore() {
        isLoading = true
        errorMessage = nil
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

// MARK: - SKProductsRequestDelegate

extension SubscriptionManager: SKProductsRequestDelegate {

    func productsRequest(_ request: SKProductsRequest,
                         didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
            self.isLoading = false
            self.reconcileSelectedProduct()
        }
    }

    /// Keeps `selectedProductID` pointing at a product that actually exists.
    /// The default is monthly, but if App Store Connect doesn't have that
    /// product configured (removed, not yet approved, wrong region, etc.),
    /// StoreKit simply omits it from `response.products` with no error — so
    /// without this, the paywall would show no plan selected and "Subscribe"
    /// would stay permanently disabled. Falls through the preferred order,
    /// then to whatever's actually available. Never overrides an already
    /// valid selection, so a user's own tap is respected across a re-fetch.
    private func reconcileSelectedProduct() {
        guard !products.isEmpty,
              !products.contains(where: { $0.productIdentifier == selectedProductID })
        else { return }

        if let match = Self.preferredProductOrder.first(where: { pid in
            products.contains { $0.productIdentifier == pid }
        }) {
            selectedProductID = match
        } else if let first = products.first {
            selectedProductID = first.productIdentifier
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            if request is SKReceiptRefreshRequest {
                // Can't verify grandfather status without receipt — assume not grandfathered
                print("SubscriptionManager: receipt refresh failed — \(error.localizedDescription)")
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func requestDidFinish(_ request: SKRequest) {
        if request is SKReceiptRefreshRequest {
            // Receipt was refreshed — re-run the grandfather check
            DispatchQueue.main.async { self.checkGrandfatheredStatus() }
        }
    }
}

// MARK: - SKPaymentTransactionObserver

extension SubscriptionManager: SKPaymentTransactionObserver {

    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        for tx in transactions {
            switch tx.transactionState {
            case .purchased, .restored:
                let pid = tx.payment.productIdentifier
                queue.finishTransaction(tx)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.markSubscribed(productID: pid)
                }
            case .failed:
                queue.finishTransaction(tx)
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let err = tx.error as? SKError, err.code != .paymentCancelled {
                        self.errorMessage = err.localizedDescription
                    }
                }
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        DispatchQueue.main.async {
            self.isLoading = false
            if !self.isSubscribed {
                self.errorMessage = "No previous subscription found."
            }
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
}
