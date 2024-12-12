//
//  ListView.swift
//  LoopSpeak
//
//  Created by Pieter Yoshua Natanael on 09/12/24.
//

import SwiftUI

struct TextEntry: Identifiable, Codable {
    let id: UUID
    var text: String
    var previewText: String
    var dateCreated: Date
    
    init(text: String) {
        self.id = UUID()
        self.text = text
        // Create preview text (first 3 lines or first 100 characters)
        let lines = text.components(separatedBy: .newlines)
        self.previewText = lines.prefix(3).joined(separator: "\n")
        self.dateCreated = Date()
    }
}

struct ListView: View {
    @State private var savedTexts: [TextEntry] = []
    @State private var newText: String = ""
    @State private var showCopyConfirmation: Bool = false
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                // Text Input Section
                VStack {
                    TextEditor(text: $newText)
                        .frame(height: 150)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .padding()
                        .focused($isTextEditorFocused)
                    
                    HStack {
                       
                        
                        Button(action: saveText) {
                            Text("Save Text")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(newText.isEmpty)
                        
                        // Paste Button
                        Button(action: {
                            newText = UIPasteboard.general.string ?? ""
                        }) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal)
                        
                        Button(action: {
                            newText = ""
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.purple)
                        }
                                 
                    }
                }
                
                // Saved Texts List
                List {
                    ForEach(savedTexts) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.previewText)
                                    .font(.caption)
                                    .lineLimit(3)
                                
                                Text(entry.dateCreated, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                // Copy text to clipboard
                                UIPasteboard.general.string = entry.text
                                showCopyConfirmation = true
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
            .navigationTitle("Text Library")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextEditorFocused = false
                    }
                }
            }
            .alert(isPresented: $showCopyConfirmation) {
                Alert(
                    title: Text("Text Copied"),
                    message: Text("The text has been copied to clipboard."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside text editor
                isTextEditorFocused = false
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    
    // Save text to the list
    func saveText() {
        guard !newText.isEmpty else { return }
        
        let newEntry = TextEntry(text: newText)
        savedTexts.append(newEntry)
        
        // Clear text after saving
        newText = ""
        
        // Dismiss keyboard
        isTextEditorFocused = false
        
        // Save to UserDefaults
        saveToUserDefaults()
    }
    
    // Delete entries by IndexSet (used by .onDelete)
    func deleteEntries(at offsets: IndexSet) {
        savedTexts.remove(atOffsets: offsets)
        saveToUserDefaults()
    }
    
    // Save texts to UserDefaults for persistence
    func saveToUserDefaults() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(savedTexts) {
            UserDefaults.standard.set(encoded, forKey: "savedTexts")
        }
    }
    
    // Load texts from UserDefaults on view initialization
    init() {
        if let savedTextsData = UserDefaults.standard.object(forKey: "savedTexts") as? Data {
            let decoder = JSONDecoder()
            if let loadedTexts = try? decoder.decode([TextEntry].self, from: savedTextsData) {
                _savedTexts = State(initialValue: loadedTexts)
            }
        }
    }
}

// Preview for SwiftUI
struct ListView_Previews: PreviewProvider {
    static var previews: some View {
        ListView()
    }
}
