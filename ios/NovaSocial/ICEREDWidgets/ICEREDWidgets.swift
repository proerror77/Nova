import WidgetKit
import SwiftUI

@main
struct ICEREDWidgets: WidgetBundle {
    var body: some Widget {
        UnreadMessagesWidget()
        ProfileStatsWidget()
        ActivitySummaryWidget()
        FeedHighlightsWidget()
        AliceQuickWidget()
    }
}
