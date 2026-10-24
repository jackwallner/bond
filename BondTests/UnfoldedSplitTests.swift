import CoreGraphics
import Testing

@testable import Bond

struct UnfoldedSplitTests {
    // MARK: — When to split

    @Test func compact_width_never_splits() {
        #expect(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 455.5...495.5) == nil)
    }

    @Test func folded_outer_display_stays_single() {
        #expect(UnfoldedSplit.make(width: 466, isRegularWidth: true, fold: nil) == nil)
    }

    @Test func regular_width_too_narrow_for_two_panes_stays_single() {
        // The unfolded Duo held in portrait: 669 pt can't hold two 360 pt panes.
        #expect(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil) == nil)
        #expect(UnfoldedSplit.make(width: 719, isRegularWidth: true, fold: nil) == nil)
    }

    // MARK: — Where the panes go

    @Test func panes_meet_the_fold_edges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 455.5...495.5)
        #expect(split == UnfoldedSplit(primaryWidth: 455.5, secondaryX: 495.5, secondaryWidth: 455.5))
    }

    @Test func zero_width_fold_splits_at_the_line() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 475.5...475.5)
        #expect(split == UnfoldedSplit(primaryWidth: 475.5, secondaryX: 475.5, secondaryWidth: 475.5))
    }

    @Test func no_fold_splits_evenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        #expect(split == UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    @Test func off_centre_fold_that_starves_a_pane_falls_back_to_even() {
        let split = UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 300...340)
        #expect(split == UnfoldedSplit(primaryWidth: 400, secondaryX: 400, secondaryWidth: 400))
    }

    @Test func every_split_leaves_two_usable_panes_inside_the_width() {
        for width in stride(from: CGFloat(720), through: 1400, by: 7.5) {
            let folds: [ClosedRange<CGFloat>?] = [nil, (width / 2 - 20)...(width / 2 + 20), 100...140]
            for fold in folds {
                let panes = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: fold)
                #expect(panes != nil)
                guard let panes else { continue }
                #expect(panes.primaryWidth >= UnfoldedSplit.minimumPaneWidth)
                #expect(panes.secondaryWidth >= UnfoldedSplit.minimumPaneWidth)
                #expect(panes.secondaryX >= panes.primaryWidth)
                #expect(panes.secondaryX + panes.secondaryWidth == width)
            }
        }
    }
}

/// Where the leading pane's rows stop above the floating tab bar.
struct PaneCutTests {
    @Test func folded_has_no_clearance() {
        #expect(TabBarClearance.make(isSplit: false, barInset: 84) == TabBarClearance(hidden: 0, contentPadding: 0))
    }

    @Test func split_ends_content_a_gap_above_the_bar() {
        let clearance = TabBarClearance.make(isSplit: true, barInset: 84)
        #expect(clearance == TabBarClearance(hidden: 84 + TabBarClearance.gap, contentPadding: TabBarClearance.gap))
    }

    @Test func rows_above_the_line_leave_it_in_place() {
        let rows = [PaneCut.Row(minY: 140, maxY: 312), PaneCut.Row(minY: 330, maxY: 573)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 573, card: nil))
    }

    @Test func a_sliced_card_is_hidden_whole() {
        // Run5's Reminders pane: the first Up next row ran under the bar.
        let rows = [PaneCut.Row(minY: 277, maxY: 439), PaneCut.Row(minY: 503, maxY: 603)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 503, card: nil))
    }

    @Test func a_sliced_list_row_closes_its_card_above_the_separator() {
        // Run5's Settings pane: Terracotta fit, Pink was sliced.
        let rows = [PaneCut.Row(minY: 512, maxY: 563, card: .groupedList),
                    PaneCut.Row(minY: 563, maxY: 614, card: .groupedList)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 562, card: .groupedList))
    }

    @Test func a_header_goes_with_its_hidden_first_row() {
        let rows = [PaneCut.Row(minY: 439, maxY: 456),
                    PaneCut.Row(minY: 484, maxY: 501, keepsWithNext: true),
                    PaneCut.Row(minY: 503, maxY: 603, card: .groupedList)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 484, card: nil))
    }

    @Test func a_header_whose_row_starts_below_the_line_goes_too() {
        let rows = [PaneCut.Row(minY: 548, maxY: 565, keepsWithNext: true),
                    PaneCut.Row(minY: 580, maxY: 640)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 548, card: nil))
    }

    @Test func a_header_above_visible_rows_stays() {
        let rows = [PaneCut.Row(minY: 250, maxY: 267, keepsWithNext: true),
                    PaneCut.Row(minY: 277, maxY: 439),
                    PaneCut.Row(minY: 503, maxY: 603)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 503, card: nil))
    }

    @Test func a_tall_row_is_sliced_rather_than_empty_the_pane() {
        let rows = [PaneCut.Row(minY: 573 - PaneCut.maxLift - 1, maxY: 900)]
        #expect(PaneCut.make(line: 573, rows: rows) == PaneCut(y: 573, card: nil))
    }
}

/// The editor's love-language chips wrap in the Duo pane.
struct FlowRowsTests {
    @Test func chips_that_fit_share_a_row() {
        let rows = FlowRows.make(sizes: [CGSize(width: 100, height: 30), CGSize(width: 100, height: 30)], width: 300, spacing: 8)
        #expect(rows.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0)])
        #expect(rows.size == CGSize(width: 208, height: 30))
    }

    @Test func a_chip_that_would_pass_the_edge_wraps() {
        let sizes = [CGSize(width: 180, height: 34), CGSize(width: 150, height: 34), CGSize(width: 140, height: 34)]
        let rows = FlowRows.make(sizes: sizes, width: 395, spacing: 8)
        #expect(rows.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 188, y: 0), CGPoint(x: 0, y: 42)])
        #expect(rows.size.height == 76)
        #expect(rows.size.width <= 395)
    }

    @Test func a_chip_wider_than_the_row_gets_its_own() {
        let rows = FlowRows.make(sizes: [CGSize(width: 50, height: 20), CGSize(width: 500, height: 20)], width: 300, spacing: 8)
        #expect(rows.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 28)])
    }
}

#if DEBUG
/// The `-DuoScreen <surface>` launch argument capture runs use to open a surface.
struct DuoScreenTests {
    @Test func reads_the_surface_after_the_flag() {
        #expect(DuoScreen.value(in: ["Bond", "-BondScreenshotSeed", "-DuoScreen", "checkin"]) == "checkin")
    }

    @Test func missing_flag_or_value_opens_nothing() {
        #expect(DuoScreen.value(in: ["Bond", "-BondScreenshotSeed"]) == nil)
        #expect(DuoScreen.value(in: ["Bond", "-DuoScreen"]) == nil)
    }
}
#endif
