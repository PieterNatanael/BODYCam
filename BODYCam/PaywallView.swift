import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    Spacer().frame(height: 32)
                    featuresSection
                    Spacer().frame(height: 32)
                    ctaSection
                    Spacer().frame(height: 20)
                    footerSection
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .overlay(closeButton, alignment: .topTrailing)
        .alert(isPresented: Binding(
            get: { subscriptionManager.errorMessage != nil },
            set: { if !$0 { subscriptionManager.errorMessage = nil } }
        )) {
            Alert(
                title: Text("Purchase Error"),
                message: Text(subscriptionManager.errorMessage ?? ""),
                dismissButton: .default(Text("OK")) {
                    subscriptionManager.errorMessage = nil
                }
            )
        }
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button(action: { presentationMode.wrappedValue.dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(white: 0.4))
        }
        .padding(.top, 12)
        .padding(.trailing, 20)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 50)

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.22), Color(white: 0.08)],
                        center: .center, startRadius: 10, endRadius: 60
                    ))
                    .frame(width: 110, height: 110)
                    .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundColor(Color(white: 0.75))
            }

            Text("LB CAMERA PRO")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(4)

            Text("Unlock the full app")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(icon: "play.rectangle.fill",    text: "Full video playback, no 15 second cap")
            featureRow(icon: "square.and.arrow.down.fill", text: "Save photos and videos to your library")
            featureRow(icon: "square.and.arrow.up.fill",   text: "Share photos and videos")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.1))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(white: 0.2), lineWidth: 1))
        )
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Color(white: 0.65))
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(white: 0.8))
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Plan cards
            if subscriptionManager.sortedProducts.isEmpty {
                ProgressView().accentColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(subscriptionManager.sortedProducts, id: \.productIdentifier) { product in
                        planCard(for: product)
                    }
                }
            }

            // Subscribe
            Button(action: { subscriptionManager.purchase() }) {
                ZStack {
                    if subscriptionManager.isLoading {
                        ProgressView().accentColor(.black)
                    } else {
                        Text("SUBSCRIBE")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(white: 0.9))
                .cornerRadius(10)
            }
            .disabled(subscriptionManager.isLoading || subscriptionManager.selectedProduct == nil)

            // Restore
            Button(action: { subscriptionManager.restore() }) {
                Text("Restore Purchases")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .underline()
            }
            .disabled(subscriptionManager.isLoading)

            // Apple-required subscription disclosure
            subscriptionDisclosure
        }
    }

    // MARK: - Subscription disclosure (required by Apple guideline 3.1.2)

    private var subscriptionDisclosure: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Color(white: 0.15))
                .frame(height: 1)

            Text(disclosureText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.32))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var disclosureText: String {
        let selected = subscriptionManager.selectedProductID
        let period: String
        switch selected {
        case "com.lb.pro.weekly":  period = "week"
        case "com.lb.pro.monthly": period = "month"
        default:                   period = "year"
        }
        return """
        Payment will be charged to your Apple ID account at confirmation of purchase. \
        Your subscription automatically renews for the same price and duration unless cancelled \
        at least 24 hours before the end of the current \(period). \
        Your account will be charged for renewal within 24 hours prior to the end of the current \(period). \
        To manage or cancel your subscription, go to Settings → [Your Name] → Subscriptions. \
        Cancellation takes effect at the end of the current billing period.
        """
    }

    // MARK: - Plan card

    private func planCard(for product: SKProduct) -> some View {
        let pid       = product.productIdentifier
        let isSelected = subscriptionManager.selectedProductID == pid
        let isBest    = pid == "com.lb.pro.yearly"

        return Button(action: { subscriptionManager.selectedProductID = pid }) {
            HStack(spacing: 14) {
                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(white: 0.9) : Color(white: 0.35), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color(white: 0.9))
                            .frame(width: 11, height: 11)
                    }
                }

                // Plan name + period
                VStack(alignment: .leading, spacing: 2) {
                    Text(planName(for: pid))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(periodLabel(for: pid))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                }

                Spacer()

                // Price + period + best-value badge
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(product.localizedPrice ?? "")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                        Text(pricePeriod(for: pid))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    }
                    if isBest {
                        Text("BEST VALUE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.85))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(white: 0.16) : Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color(white: 0.55) : Color(white: 0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan helpers

    private func planName(for pid: String) -> String {
        switch pid {
        case "com.lb.pro.weekly":  return "Weekly"
        case "com.lb.pro.monthly": return "Monthly"
        default:                   return "Yearly"
        }
    }

    private func periodLabel(for pid: String) -> String {
        switch pid {
        case "com.lb.pro.weekly":  return "billed every 7 days · auto-renews"
        case "com.lb.pro.monthly": return "billed every 30 days · auto-renews"
        default:                   return "billed every 365 days · auto-renews"
        }
    }

    private func pricePeriod(for pid: String) -> String {
        switch pid {
        case "com.lb.pro.weekly":  return "/ week"
        case "com.lb.pro.monthly": return "/ month"
        default:                   return "/ year"
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("Bought LB Camera before April 2026? Your full access is restored automatically, no action needed.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.32))
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Link("Privacy Policy",
                     destination: URL(string: "https://gogoodmood.com/apps/en/lbc/privacy/")!)
                Link("Terms of Use",
                     destination: URL(string: "https://gogoodmood.com/apps/en/lbc/terms/")!)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color(white: 0.28))
        }
        .padding(.top, 4)
    }
}
