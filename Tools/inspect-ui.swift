// BudsBar — accessibility inspection of the live app
// SPDX-License-Identifier: MIT
//
// Opens the menu-bar panel of the running app and dumps what the
// accessibility tree reports. This is how the live UI is verified without
// screen-recording permission.

import Cocoa
import ApplicationServices

func axv(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var x: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, a as CFString, &x) == .success ? x as AnyObject : nil
}
func axs(_ e: AXUIElement, _ a: String) -> String { axv(e, a) as? String ?? "" }
func axkids(_ e: AXUIElement) -> [AXUIElement] { (axv(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

/// Every string the element exposes, so nothing is missed by picking the
/// wrong attribute.
func axstrings(_ e: AXUIElement) -> [String] {
    var out: [String] = []
    for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXLabel", "AXSelected"] {
        let v = axs(e, attribute)
        if !v.isEmpty && !out.contains(v) { out.append(v) }
    }
    // Checkboxes and switches carry their state as a number, not a string.
    let role = axs(e, kAXRoleAttribute)
    if role == "AXCheckBox" || role == "AXRadioButton" || role == "AXSwitch" {
        if let number = axv(e, kAXValueAttribute) as? NSNumber {
            let text = number.boolValue ? "checked" : "unchecked"
            if !out.contains(text) { out.append(text) }
        }
    }
    return out
}

func dumpTree(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
    guard depth <= maxDepth else { return }
    let role = axs(e, kAXRoleAttribute)
    let strings = axstrings(e)
    var line = String(repeating: "  ", count: depth)
    line += role.isEmpty ? "<no role>" : role
    for s in strings { line += " '\(s)'" }
    print(line)
    for c in axkids(e) { dumpTree(c, depth + 1, maxDepth) }
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.budsbar.BudsBar").first else {
    print("app not running"); exit(1)
}
print("app pid: \(app.processIdentifier)")

let root = AXUIElementCreateApplication(app.processIdentifier)

// Open the panel by pressing the status item.
//
// The status item's title is dynamic: it reads the battery percentage once
// the earbuds are connected and falls back to a fixed word before that, so
// the item is located by "not one of the standard app menus" rather than by
// a fixed title.
func findStatusItem() -> AXUIElement? {
    let standardMenus = ["Apple", "BudsBar", "Edit", "View", "Window", "Help", "Format"]
    var fallback: AXUIElement?
    for bar in axkids(root) where axs(bar, kAXRoleAttribute) == "AXMenuBar" {
        for c in axkids(bar) {
            let title = axs(c, kAXTitleAttribute)
            let identifier = axs(c, "AXIdentifier")
            if identifier.contains("BudsBar") { return c }
            if standardMenus.contains(title) { continue }
            if fallback == nil { fallback = c }
        }
    }
    return fallback
}

func findPanelWindow() -> AXUIElement? {
    for other in NSWorkspace.shared.runningApplications {
        let otherRoot = AXUIElementCreateApplication(other.processIdentifier)
        let wins = (axv(otherRoot, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for w in wins {
            var ownerPID: pid_t = 0
            AXUIElementGetPid(w, &ownerPID)
            if ownerPID == app.processIdentifier {
                return w
            }
        }
    }
    return nil
}

var panel: AXUIElement?
if let item = findStatusItem() {
    print("status item found; pressing it")
    for attempt in 1...6 {
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
            if let w = findPanelWindow() {
                panel = w
                break
            }
        }
        if panel != nil { break }
        print("  attempt \(attempt): panel window not found yet")
    }
} else {
    print("status item not found in the menu bar")
}

guard let panel else {
    print("panel did not open")
    exit(2)
}

print("\n--- panel found, dumping the tree ---")
dumpTree(panel, 1, 8)
print("done")
