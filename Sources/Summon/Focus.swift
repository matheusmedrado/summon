import ApplicationServices

private let systemWide: AXUIElement = {
    let element = AXUIElementCreateSystemWide()
    // Called from inside the event tap: never wait long on a busy app.
    AXUIElementSetMessagingTimeout(element, 0.1)
    return element
}()

/// True while the focused element is somewhere you type: a text field,
/// text area, search field, or a rename box in Finder.
func isTypingInTextField() -> Bool {
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return false }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
    return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role as? String ?? "")
}
