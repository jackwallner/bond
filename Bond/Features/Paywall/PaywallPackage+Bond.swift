import Foundation
import RevenueCat

enum BondPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension BondPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier]
                .map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains("lifetime") }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains("yearly") || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains("monthly") }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var bondPackageKind: BondPackageKind { BondPackageKind(package: self) }

    var bondDisplayName: String {
        switch bondPackageKind {
        case .lifetime: return "Lifetime"
        case .yearly:   return "Yearly"
        case .monthly:  return "Monthly"
        case .other:    return storeProduct.localizedTitle
        }
    }

    var bondPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else {
            return storeProduct.localizedPriceString
        }
        let unit: String
        switch period.unit {
        case .day:   unit = period.value == 1 ? "day" : "days"
        case .week:  unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year:  unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        }
        return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
    }

    var bondIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day:   unit = period.value == 1 ? "day" : "days"
        case .week:  unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year:  unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.unit == .week {
            return "\(period.value * 7)-day free trial"
        }
        return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
    }

    /// Trial length in days, if the package has a free-trial intro offer.
    var bondTrialDays: Int? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day:   return period.value
        case .week:  return period.value * 7
        case .month: return period.value * 30
        case .year:  return period.value * 365
        @unknown default: return nil
        }
    }

    /// Localized per-week price string (e.g. "$0.96/wk"), derived from the
    /// subscription period. Returns nil for one-shot products.
    var bondPricePerWeekLabel: String? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let weeks: Decimal
        switch period.unit {
        case .day:   weeks = Decimal(period.value) / 7
        case .week:  weeks = Decimal(period.value)
        case .month: weeks = Decimal(period.value) * Decimal(string: "4.345")!
        case .year:  weeks = Decimal(period.value) * 52
        @unknown default: return nil
        }
        guard weeks > 0 else { return nil }
        let perWeek = storeProduct.price / weeks
        return formatted(price: perWeek) + "/wk"
    }

    /// Approximate monthly price for this package (used for savings math).
    var bondMonthlyPriceValue: Decimal? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .day:   months = Decimal(period.value) / 30
        case .week:  months = Decimal(period.value) / Decimal(string: "4.345")!
        case .month: months = Decimal(period.value)
        case .year:  months = Decimal(period.value) * 12
        @unknown default: return nil
        }
        guard months > 0 else { return nil }
        return storeProduct.price / months
    }

    /// Percent savings vs the supplied monthly package, e.g. 60 for "Save 60%".
    /// Returns nil if either side lacks a usable monthly equivalent or savings ≤ 0.
    func bondSavingsPercent(comparedToMonthly monthly: Package) -> Int? {
        guard
            let mine = bondMonthlyPriceValue,
            let other = monthly.bondMonthlyPriceValue,
            other > 0,
            mine < other
        else { return nil }
        let ratio = (other - mine) / other
        let percent = NSDecimalNumber(decimal: ratio * 100).doubleValue
        let rounded = Int(percent.rounded())
        return rounded > 0 ? rounded : nil
    }

    private func formatted(price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = storeProduct.priceFormatter?.locale ?? .current
        if let currencyCode = storeProduct.currencyCode {
            formatter.currencyCode = currencyCode
        }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: price))
            ?? storeProduct.localizedPriceString
    }
}

extension Offering {
    var bondSortedPackages: [Package] {
        availablePackages.sorted {
            let lhs = $0.bondPackageKind
            let rhs = $1.bondPackageKind
            if lhs.rawValue != rhs.rawValue { return lhs.rawValue < rhs.rawValue }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var bondPaywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}
