import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// One spring in Fathom's motion language.
///
/// Apple's fluid-interface vocabulary describes a spring by how quickly it
/// reaches its target ([response], in seconds) and how much it overshoots
/// ([dampingRatio], where 1.0 does not). Flutter's [SpringDescription] takes
/// mass/stiffness/damping instead, so the conversion lives here once: every
/// surface names the same feel instead of carrying its own magic constants.
///
/// A spring has no duration. Retargeting it mid-flight keeps the current value
/// and velocity, which is what makes a gesture reversible without a seam.
@immutable
class FathomSpring {
  const FathomSpring({
    required this.response,
    this.dampingRatio = 1.0,
    this.mass = 1.0,
  })  : assert(response > 0),
        assert(dampingRatio > 0),
        assert(mass > 0);

  /// How quickly the value reaches its target, in seconds.
  final double response;

  /// Overshoot: 1.0 settles without bouncing, below 1.0 overshoots.
  final double dampingRatio;

  final double mass;

  /// Natural frequency squared, in the units [SpringDescription] expects.
  double get stiffness {
    final omega = 2 * math.pi / response;
    return omega * omega * mass;
  }

  SpringDescription get description => SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: dampingRatio,
      );

  /// A simulation from [from] to [to], continuing at [velocity] units/second.
  ///
  /// [from] must be the value currently on screen, never the last target: that
  /// is what lets an interrupted move resume from where the eye last saw it.
  SpringSimulation simulation({
    required double from,
    required double to,
    double velocity = 0,
  }) {
    return SpringSimulation(description, from, to, velocity);
  }

  @override
  bool operator ==(Object other) {
    return other is FathomSpring &&
        other.response == response &&
        other.dampingRatio == dampingRatio &&
        other.mass == mass;
  }

  @override
  int get hashCode => Object.hash(response, dampingRatio, mass);

  @override
  String toString() =>
      'FathomSpring(response: $response, ratio: $dampingRatio)';
}

/// The springs Fathom uses, named by the job they do rather than by size.
///
/// Overshoot is deliberate only where a gesture carried momentum. A control
/// that merely changed state settles cleanly; a card that was flicked may
/// bounce, because the finger already supplied the energy.
abstract final class FathomMotion {
  /// Touch feedback: pressed scale, slider thickness. Fast, tiny overshoot so
  /// the control answers the finger instead of easing at it.
  static const press = FathomSpring(response: 0.20, dampingRatio: 0.86);

  /// A committed state change: switch thumb, snapped list height, chip.
  /// Slightly slower than [press], no bounce.
  static const snap = FathomSpring(response: 0.30);

  /// A surface moving because the user navigated, not because they dragged.
  static const standard = FathomSpring(response: 0.38);

  /// A drag release or a flick. Under-damped, matched to Apple's drawer and
  /// rotation feel; the carried velocity supplies the overshoot.
  static const momentum = FathomSpring(response: 0.40, dampingRatio: 0.80);

  /// A large surface arriving: covers, list cascades, page content. The longer
  /// response keeps the travel readable instead of snapping into place.
  static const gentle = FathomSpring(response: 0.50);
}

/// A spring-shaped curve for route transitions, which Flutter drives by
/// elapsed time rather than by a simulation.
///
/// A [PageRoute] owns an [AnimationController] with a duration; replacing that
/// machinery to run a real simulation would fight the navigator, and a route
/// is not something a finger drags. This curve gives the transition the same
/// decelerating arrival as the springs above, starting from rest and settling
/// exactly at 1. It is critically damped on purpose: route opacity and layout
/// must never overshoot their end state.
class FathomSpringCurve extends Curve {
  const FathomSpringCurve();

  /// Normalized time constant. Large enough that the motion reads as a settle
  /// inside the route window rather than an abrupt stop.
  static const double _omega = 7.0;

  /// The raw response is not exactly 1 at t = 1; dividing by its value keeps
  /// the curve's endpoint honest, so a route never stops a hair short.
  static final double _settle = 1 - math.exp(-_omega) * (1 + _omega);

  @override
  double transformInternal(double t) {
    final x = t.clamp(0.0, 1.0);
    final value = 1 - math.exp(-_omega * x) * (1 + _omega * x);
    return (value / _settle).clamp(0.0, 1.0);
  }
}

/// The motion every modal shares: bottom sheets and dialogs.
///
/// The navigator drives a modal with a timed controller, so the spring shape
/// comes from [FathomSpringCurve]. Long enough for the arrival to read on a
/// surface that covers half the screen, short enough that dismissing never
/// waits. The exit accelerates away instead of decelerating into the barrier.
const AnimationStyle kModalMotion = AnimationStyle(
  duration: Duration(milliseconds: 300),
  reverseDuration: Duration(milliseconds: 220),
  curve: FathomSpringCurve(),
  reverseCurve: Curves.easeInCubic,
);

/// Animates a double toward [value] with a spring, from the value currently on
/// screen.
///
/// This is the spring counterpart of the implicit animations Flutter ships:
/// a target change retargets the physics instead of restarting a timed tween,
/// and the current velocity is handed to the new simulation. A second change
/// mid-flight therefore blends instead of jumping, which is the behaviour a
/// user touching the control expects.
///
/// [immediate] exists for controls that are already tracking a finger. A
/// slider must follow the pointer 1:1 and then spring only when the value
/// changes from outside, so it snaps while dragging and animates otherwise.
///
/// [animateOnMount] makes the first appearance travel from zero; without it
/// the widget starts at [value], so a rebuild never replays an entrance.
class SpringValue extends StatefulWidget {
  const SpringValue({
    super.key,
    required this.value,
    required this.builder,
    this.spring = FathomMotion.standard,
    this.immediate = false,
    this.animateOnMount = false,
  });

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final FathomSpring spring;

  /// Snaps to [value] instead of animating. Use while a gesture owns the value.
  final bool immediate;

  /// Starts at zero and springs to [value] on the first frame.
  final bool animateOnMount;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.animateOnMount ? 0 : widget.value,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animateOnMount && widget.value != 0) {
      _controller.animateWith(
        widget.spring.simulation(from: 0, to: widget.value),
      );
    }
  }

  @override
  void didUpdateWidget(SpringValue oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.immediate) {
      _controller.value = widget.value;
      return;
    }
    if (widget.value == oldWidget.value && widget.spring == oldWidget.spring) {
      return;
    }

    _controller.animateWith(
      widget.spring.simulation(
        from: _controller.value,
        to: widget.value,
        velocity: _controller.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // A spring stops inside its tolerance rather than on its target, so the
        // last thousandths of the travel are never reached by the simulation.
        // Reading the target whenever the controller is at rest makes a
        // settled control show exactly the value it was given; while it moves,
        // the presentation value is what the eye follows.
        final value =
            _controller.isAnimating ? _controller.value : widget.value;
        return widget.builder(context, value);
      },
    );
  }
}
