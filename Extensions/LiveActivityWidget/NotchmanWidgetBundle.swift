import SwiftUI
import WidgetKit

@main
struct NotchmanWidgetBundle: WidgetBundle {
    var body: some Widget {
        NotchmanLiveActivity()
        if #available(iOSApplicationExtension 18.0, *) {
            TLDRControl()
        }
    }
}
