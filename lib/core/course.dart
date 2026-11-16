import 'package:latlong2/latlong.dart';

import 'elevation.dart';
import 'route.dart';

/// A stretch of a course at one grade.
typedef Segment = ({double meters, double grade});

/// A made-up course in the Compete catalog: no real road, just grades, so
/// every rider gets exactly the same course with no data to fetch.
class Course {
  Course(this.id, this.name, this.blurb, this.segments);

  /// Ghosts are matched to courses by this. Changing a course's segments
  /// must come with a new id, or old ghosts would race a different course.
  final String id;
  final String name;
  final String blurb;
  final List<Segment> segments;

  double get lengthMeters => segments.fold(0.0, (a, s) => a + s.meters);

  /// The course as something the ride code can ride (and simulate). Its path
  /// is a straight line on the equator: it is never drawn, the race view
  /// shows the profile instead. One instance, so a run can be recognised.
  late final SavedRoute route = () {
    const step = 25.0;
    final ds = <double>[0], es = <double>[0];
    for (final s in segments) {
      final n = (s.meters / step).ceil();
      for (var i = 1; i <= n; i++) {
        ds.add(ds.last + s.meters / n);
        es.add(es.last + s.meters / n * s.grade / 100);
      }
    }
    final end = LatLng(0, lengthMeters / 111319.49); // metres per degree there
    return SavedRoute(name, [const LatLng(0, 0), end], [const LatLng(0, 0), end])
        .withElevation(ElevationProfile.fromSamples(ds, es));
  }();
}

Segment _s(double km, double grade) => (meters: km * 1000, grade: grade);

/// The catalog. Ids end in a version: see [Course.id].
final courses = <Course>[
  Course('flat-out-v1', 'Flat Out', 'Ten kilometres, nowhere to hide.',
      [_s(10, 0)]),
  Course('rollers-v1', 'Rolling Hills', 'Short ups and downs that reward '
      'pushing over the top.', [
    for (var i = 0; i < 6; i++) ...[_s(0.8, 3.5), _s(0.8, -3)],
    _s(1, 0),
  ]),
  Course('long-drag-v1', 'The Long Drag', 'A flat run-in, then six '
      'kilometres at a steady 6%.', [_s(1, 0), _s(6, 6), _s(0.5, 0)]),
  Course('pyramid-v1', 'Pyramid', 'Each climb steeper than the last, then '
      'back down the scale.', [
    for (final g in const [2.0, 4.0, 6.0, 8.0, 6.0, 4.0, 2.0]) ...[_s(0.6, g), _s(0.4, 0)],
  ]),
  Course('short-sharp-v1', 'Short & Sharp', 'One kilometre at 10%. All '
      'out.', [_s(0.5, 0), _s(1, 10), _s(0.3, 0)]),
  Course('coast-loop-v1', 'Coast Loop', 'Twenty kilometres of flat with '
      'three bumps, back where you started.', [
    for (var i = 0; i < 3; i++) ...[_s(4, 0), _s(1, 4), _s(1, -4)],
    _s(2, 0),
  ]),
];

Course? courseById(String id) => courses.where((c) => c.id == id).firstOrNull;
