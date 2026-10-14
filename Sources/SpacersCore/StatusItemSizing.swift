import Foundation

public enum StatusItemSizing {
    /// Center owns runtime sizing while enabled. Otherwise reconcile the live
    /// length, not the previous saved width: both saved widths can be 24 while
    /// Center has grown the native item to hundreds of points.
    public static func widthToApply(for item: ItemConfiguration, currentWidth: Double) -> Double? {
        guard item.kind != .flexSpacer || item.flex?.isEnabled != true,
              currentWidth != item.width else { return nil }
        return item.width
    }
}
