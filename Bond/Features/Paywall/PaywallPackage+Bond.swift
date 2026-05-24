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
