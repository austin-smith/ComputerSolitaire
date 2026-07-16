import XCTest
@testable import Computer_Solitaire

/// The motion policy is the single gate every gameplay animation and
/// completion delay routes through; these tests pin its contract — the speed
/// catalog's stored scales, the raw-value fallback that protects old saved
/// defaults, the Reduce Motion clamp, and the builders going nil (apply
/// without animating) whenever motion is off.
@MainActor
final class MotionPolicyTests: XCTestCase {
    func testAnimationSpeedScales() {
        XCTAssertEqual(AnimationSpeed.normal.scale, 1)
        XCTAssertEqual(AnimationSpeed.fast.scale, 0.5)
        XCTAssertEqual(AnimationSpeed.instant.scale, 0)
        XCTAssertEqual(AnimationSpeed.defaultValue, .normal)
    }

    func testFromRawValueRoundTripsEveryOption() {
        for speed in AnimationSpeed.all {
            XCTAssertEqual(AnimationSpeed.from(rawValue: speed.id), speed)
        }
    }

    func testFromRawValueFallsBackToDefaultOnUnknownID() {
        XCTAssertEqual(AnimationSpeed.from(rawValue: "warp"), .normal)
        XCTAssertEqual(AnimationSpeed.from(rawValue: ""), .normal)
    }

    func testPolicyUsesSpeedScaleWithoutReduceMotion() {
        for speed in AnimationSpeed.all {
            let policy = MotionPolicy(speed: speed, reduceMotion: false)
            XCTAssertEqual(policy.scale, speed.scale)
        }
    }

    func testReduceMotionClampsEverySpeedToInstant() {
        for speed in AnimationSpeed.all {
            let policy = MotionPolicy(speed: speed, reduceMotion: true)
            XCTAssertEqual(policy.scale, 0)
            XCTAssertTrue(policy.isInstant)
            XCTAssertNil(policy.spring(response: 0.35, dampingFraction: 0.86))
        }
    }

    func testIsInstantOnlyForZeroScale() {
        XCTAssertFalse(MotionPolicy(speed: .normal, reduceMotion: false).isInstant)
        XCTAssertFalse(MotionPolicy(speed: .fast, reduceMotion: false).isInstant)
        XCTAssertTrue(MotionPolicy(speed: .instant, reduceMotion: false).isInstant)
    }

    func testDurationScalesWithSpeed() {
        XCTAssertEqual(MotionPolicy(speed: .normal, reduceMotion: false).duration(0.32), 0.32)
        XCTAssertEqual(MotionPolicy(speed: .fast, reduceMotion: false).duration(0.32), 0.16)
        XCTAssertEqual(MotionPolicy(speed: .instant, reduceMotion: false).duration(0.32), 0)
        XCTAssertEqual(MotionPolicy(speed: .normal, reduceMotion: true).duration(0.32), 0)
    }

    func testBuildersReturnAnimationsWhenMotionIsOn() {
        for speed in [AnimationSpeed.normal, .fast] {
            let policy = MotionPolicy(speed: speed, reduceMotion: false)
            XCTAssertNotNil(policy.spring(response: 0.35, dampingFraction: 0.86))
            XCTAssertNotNil(policy.easeOut(0.2))
            XCTAssertNotNil(policy.easeInOut(0.32))
        }
    }

    func testBuildersReturnNilWhenInstant() {
        let policy = MotionPolicy(speed: .instant, reduceMotion: false)
        XCTAssertNil(policy.spring(response: 0.35, dampingFraction: 0.86))
        XCTAssertNil(policy.easeOut(0.2))
        XCTAssertNil(policy.easeInOut(0.32))
    }
}
