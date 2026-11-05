import Foundation

public enum StatusItemSizing {
    /// The one-point emergency width is temporary. Pausing or capturing a
    /// layout keeps the existing six-point manual/configuration minimum.
    public static func savedFlexWidth(from runtimeWidth: Double) -> Double {
        max(6, runtimeWidth)
    }

    /// Center owns runtime sizing while enabled. Otherwise reconcile the live
    /// length, not the previous saved width: both saved widths can be 24 while
    /// Center has grown the native item to hundreds of points.
    public static func widthToApply(for item: ItemConfiguration, currentWidth: Double) -> Double? {
        guard item.kind != .flexSpacer || item.flex?.isEnabled != true,
              currentWidth != item.width else { return nil }
        return item.width
    }
}
