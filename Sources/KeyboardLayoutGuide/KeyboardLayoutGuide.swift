//
//  Keyboard+LayoutGuide.swift
//  KeyboardLayoutGuide
//
//  Created by Sacha DSO on 14/11/2017.
//  Copyright © 2017 freshos. All rights reserved.
//

import UIKit

public class Keyboard {
    public static let shared = Keyboard()
    var currentHeight: CGFloat = 0

    /// If you do know you're presenting a modal in either `.formSheet` style,
    /// set this field to fix unexpected behavior of this Library.
    public weak var presentedViewController: UIViewController?
}

extension UIView {
    private enum Identifiers {
        static var usingSafeArea = "KeyboardLayoutGuideUsingSafeArea"
        static var notUsingSafeArea = "KeyboardLayoutGuide"
    }

    /// A layout guide representing the inset for the keyboard.
    /// Use this layout guide’s top anchor to create constraints pinning to the top of the keyboard or the bottom of safe area.
    public var keyboardLayoutGuide: UILayoutGuide {
        getOrCreateKeyboardLayoutGuide(identifier: Identifiers.usingSafeArea, usesSafeArea: true)
    }

    /// A layout guide representing the inset for the keyboard.
    /// Use this layout guide’s top anchor to create constraints pinning to the top of the keyboard or the bottom of the view.
    public var keyboardLayoutGuideNoSafeArea: UILayoutGuide {
        getOrCreateKeyboardLayoutGuide(identifier: Identifiers.notUsingSafeArea, usesSafeArea: false)
    }

    private func getOrCreateKeyboardLayoutGuide(identifier: String, usesSafeArea: Bool) -> UILayoutGuide {
        if let existing = layoutGuides.first(where: { $0.identifier == identifier }) {
            return existing
        }
        let new = KeyboardLayoutGuide()
        new.usesSafeArea = usesSafeArea
        new.identifier = identifier
        addLayoutGuide(new)
        new.setUp()
        return new
    }
}

open class KeyboardLayoutGuide: UILayoutGuide {
    public var usesSafeArea = true {
        didSet {
            updateBottomAnchor()
        }
    }

    private var bottomConstraint: NSLayoutConstraint?

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init(notificationCenter: NotificationCenter = NotificationCenter.default) {
        super.init()
        // Observe keyboardWillChangeFrame notifications
        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardDidChangeFrame(_:)),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
    }

    internal func setUp() {
        guard let view = owningView else { return }
        NSLayoutConstraint.activate(
            [
                heightAnchor.constraint(equalToConstant: Keyboard.shared.currentHeight),
                leftAnchor.constraint(equalTo: view.leftAnchor),
                rightAnchor.constraint(equalTo: view.rightAnchor),
            ]
        )
        updateBottomAnchor()
    }

    func updateBottomAnchor() {
        if let bottomConstraint = bottomConstraint {
            bottomConstraint.isActive = false
        }

        guard let view = owningView else { return }

        let viewBottomAnchor: NSLayoutYAxisAnchor
        if #available(iOS 11.0, *), usesSafeArea {
            viewBottomAnchor = view.safeAreaLayoutGuide.bottomAnchor
        } else {
            viewBottomAnchor = view.bottomAnchor
        }

        bottomConstraint = bottomAnchor.constraint(equalTo: viewBottomAnchor)
        bottomConstraint?.isActive = true
    }

    @objc
    private func keyboardDidChangeFrame(_ note: Notification) {
        guard note.hasBottomDifference(in: owningView) else {
            return
        }

        if var height = note.keyboardHeight(in: owningView), let duration = note.animationDuration {
            if #available(iOS 11.0, *), usesSafeArea, height > 0, let bottom = owningView?.safeAreaInsets.bottom {
                height -= bottom
            }
            heightConstraint?.constant = height
            if duration > 0.0 {
                UIView.animate(withDuration: 0.2) {
                    self.animate(note)
                }
            }
            Keyboard.shared.currentHeight = height
        }
    }

    @objc
    private func keyboardWillChangeFrame(_ note: Notification) {
        guard !note.hasBottomDifference(in: owningView) else {
            return
        }

        if var height = note.keyboardHeight(in: owningView), let duration = note.animationDuration {
            if #available(iOS 11.0, *), usesSafeArea, height > 0, let bottom = owningView?.safeAreaInsets.bottom {
                height -= bottom
            }
            heightConstraint?.constant = height
            if duration > 0.0 {
                animate(note)
            }
            Keyboard.shared.currentHeight = height
        }
    }

    private func animate(_ note: Notification) {
        if
            let owningView = self.owningView,
            isVisible(view: owningView)
        {
            self.owningView?.layoutIfNeeded()
        } else {
            UIView.performWithoutAnimation {
                self.owningView?.layoutIfNeeded()
            }
        }
    }
}

// MARK: - Helpers

extension UILayoutGuide {
    internal var heightConstraint: NSLayoutConstraint? {
        return owningView?.constraints.first {
            $0.firstItem as? UILayoutGuide == self && $0.firstAttribute == .height
        }
    }
}

extension Notification {

    func hasBottomDifference(in owningView: UIView?) -> Bool {
        guard let diff = bottomDifference(in: owningView), diff > 0 else { return false }
        return true
    }

    func bottomDifference(in owningView: UIView?) -> CGFloat? {
        // Factor in the non full screen views (iPad sheets)
        if let activeWindow = UIApplication.shared.activeWindow, let owningView = owningView {
            // Owning view's frame in the active window
            let owningFrameInRoot = owningView.convert(owningView.frame, to: activeWindow)
            // We have to ignore the part of the owning view that's outside of the active window
            // (Modal presentation)
            let intersectionFrame = activeWindow.frame.intersection(owningFrameInRoot)

            let windowHeight = activeWindow.frame.height
            let bottomDifference = windowHeight - intersectionFrame.maxY


            return bottomDifference
        }

        return nil
    }

    func keyboardHeight(in owningView: UIView?) -> CGFloat? {
        guard let keyboardFrame = userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return nil
        }

        if name == UIResponder.keyboardWillHideNotification {
            return 0.0
        }

        let keyboardMinY = keyboardFrame.cgRectValue.minY
        let screenHeight: CGFloat = UIApplication.shared.keyWindow?.bounds.height ?? UIScreen.main.bounds.height
        var height = screenHeight - keyboardMinY

        if let diff = bottomDifference(in: owningView), height > 0 {
            height -= diff
        }

        guard height != .infinity else {
            // When the app is running in multiple windows, it can happen that both windows are `foregroundActive`
            // and the intersection frame's origin can become infinite as the owning view is in the other window and the app would crash.
            return nil
        }

        return height
    }
    
    var animationDuration: CGFloat? {
        return self.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? CGFloat
    }
}

// Credits to John Gibb for this nice helper :)
// https://stackoverflow.com/questions/1536923/determine-if-uiview-is-visible-to-the-user
func isVisible(view: UIView) -> Bool {
    func isVisible(view: UIView, inView: UIView?) -> Bool {
        guard let inView = inView else { return true }
        let viewFrame = inView.convert(view.bounds, from: view)
        if viewFrame.intersects(inView.bounds) {
            return isVisible(view: view, inView: inView.superview)
        }
        return false
    }
    return isVisible(view: view, inView: view.superview)
}

extension UIApplication {

    // Finds the currently active window, This works similar to the
    // deprecated `keyWindow` however it supports multi-window'd
    // iPad apps
    var activeWindow: UIWindow? {
        if #available(iOS 13, *) {
        return connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .map { $0 as? UIWindowScene }
            .compactMap { $0 }
            .first?.windows
            .first { $0.isKeyWindow }
        } else {
            return keyWindow
        }
    }

}
