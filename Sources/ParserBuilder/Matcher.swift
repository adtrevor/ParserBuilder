import Foundation

public struct Matcher: ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    
    @inlinable
    public init(stringLiteral value: String) {
        self.matcher = .string(value)
    }
    
    @inlinable
    public init(arrayLiteral elements: Matcher...) {
        self = .init(elements)
    }
    
    @inlinable
    public init(_ matcherArray: [Matcher]) {
        self = matcherArray.reduce(Matcher.never, ||)
    }
    
    @inlinable
    public init(_ matchedString: String) {
        self.matcher = .string(matchedString)
    }
    
    @inlinable
    init(_ predicate: @escaping (Character)->Bool) {
        self.matcher = .predicate(predicate)
    }
    
    @inlinable
    public init(_ characterRange: ClosedRange<Character>) {
        self.matcher = .closedRange(characterRange)
    }
    
    @inlinable
    public init(charactersIn setString: String) {
        self = .init { character in
            let set = CharacterSet(charactersIn: setString)
            return character.unicodeScalars.allSatisfy(set.contains)
        }
    }
    
    @usableFromInline
    init(matcher: InternalMatcher) {
        self.matcher = matcher
    }
    
    @inlinable
    public static func +(lhs: Matcher, rhs: Matcher) -> Matcher {
        return Matcher(matcher: .concatenation(lhs, rhs))
    }
    
    @inlinable
    public static func ||(lhs: Matcher, rhs: Matcher) -> Matcher {
        return Matcher(matcher: .or(lhs, rhs))
    }
    
    @inlinable
    public func convenientAdvancedIndex(in string: String) -> String.Index? {
        if string.isEmpty {
            let startIndex = string.startIndex
            return advancedIndex(in: string, range: startIndex...startIndex)
        } else {
            return advancedIndex(in: string, range: string.startIndex...string.index(before: string.endIndex))
        }
        
    }
    
    @inlinable
    public func advancedIndex(in string: String, range: ClosedRange<String.Index>) -> String.Index? {
        let originalString = string
        let string: Substring
        if originalString.isEmpty {
            string = Substring(originalString)
        } else {
            string = originalString[range]
        }
        
        switch self.matcher {
        case .string(let matchedString):
            guard !matchedString.isEmpty else {
                return string.startIndex
            }
            var index = matchedString.startIndex
            let prefixed = string.prefix { character in
                guard index < matchedString.endIndex else {
                    return false
                }
                if character == matchedString[index] {
                    defer {
                        index = matchedString.index(after: index)
                    }
                    return true
                } else {
                    return false
                }
            }
            return index != matchedString.endIndex ? nil : prefixed.endIndex
            
        case .predicate(let predicate):
            if let firstCharacter = string.first, predicate(firstCharacter) {
                return string.index(after: string.startIndex)
            } else {
                return nil
            }
            
        case .or(let lhs, let rhs):
            if let first = lhs.advancedIndex(in: originalString, range: range) {
                return first
            } else if let second = rhs.advancedIndex(in: originalString, range: range) {
                return second
            } else {
                return nil
            }
            
        case .concatenation(let first, let second):
            guard let firstIndex = first.advancedIndex(in: originalString, range: range), firstIndex < string.endIndex else {
                return nil
            }
            let secondIndex = second.advancedIndex(in: originalString, range: firstIndex...string.index(before: string.endIndex))
            return secondIndex
            
        case .repeated(let matcher, let min, let max, let maxIsIncluded):
            if let max = max, max == 0 {
                return nil
            }
            var currentIndex = string.startIndex
            var repeatCount = 0
            let actualMax: Int?
            if let max = max {
                actualMax = maxIsIncluded ? max : max-1
            } else {
                actualMax = nil
            }
            
            while currentIndex < string.endIndex, repeatCount != actualMax, let newIndex = matcher.advancedIndex(in: originalString, range: currentIndex...string.index(before: string.endIndex)) {
                currentIndex = newIndex
                repeatCount += 1
            }
            
            if let min = min {
                return (repeatCount >= min) ? currentIndex : nil
            } else {
                return currentIndex
            }
            
        case .closedRange(let range):
            if let first = string.first, range.contains(first) {
                return string.index(after: string.startIndex)
            } else {
                return nil
            }
            
        }
    }
    
    @inlinable
    public func count(_ repeatRange: PartialRangeThrough<Int>) -> Matcher {
        precondition(repeatRange.upperBound >= 0)
        return Matcher(matcher: .repeated(self, nil, repeatRange.upperBound, true))
    }
    
    @inlinable
    public func count(_ repeatRange: PartialRangeUpTo<Int>) -> Matcher {
        precondition(repeatRange.upperBound >= 0)
        return Matcher(matcher: .repeated(self, nil, repeatRange.upperBound, false))
    }
    
    @inlinable
    public func count(_ repeatRange: PartialRangeFrom<Int>) -> Matcher {
        precondition(repeatRange.lowerBound >= 0)
        return Matcher(matcher: .repeated(self, repeatRange.lowerBound, nil, true))
    }
    
    @inlinable
    public func count(_ repeatRange: ClosedRange<Int>) -> Matcher {
        precondition(repeatRange.lowerBound >= 0 && repeatRange.upperBound >= 0)
        return Matcher(matcher: .repeated(self, repeatRange.lowerBound, repeatRange.upperBound, true))
    }
    
    @inlinable
    public func count(_ repeatRange: Range<Int>) -> Matcher {
        precondition(repeatRange.lowerBound >= 0 && repeatRange.upperBound >= 0)
        return Matcher(matcher: .repeated(self, repeatRange.lowerBound, repeatRange.upperBound, false))
    }
    
    @inlinable
    public func count(_ times: Int) -> Matcher {
        self.count(times...times)
    }
    
    @inlinable
    public func optional() -> Matcher {
        return self.count(0...1)
    }
    
    @inlinable
    public func atLeast(_ minimum: Int) -> Matcher {
        return self.count(minimum...)
    }
    
    //FIXME: This is not the same as `Matcher("")`, is this correct?
    @usableFromInline
    static let never: Matcher = Matcher { _ in false }
    
    @usableFromInline
    let matcher: InternalMatcher
    
    @usableFromInline
    indirect enum InternalMatcher {
        case string(String)
        case predicate((Character)->Bool)
        case concatenation(Matcher, Matcher)
        case or(Matcher, Matcher)
        case repeated(Matcher, Int?, Int?, Bool)
        case closedRange(ClosedRange<Character>)
    }
}
