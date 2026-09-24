abstract final class Routes {
  // The five shell destinations (docs/02_SCREEN_MAP.md §Navigation shell).
  static const String home = '/';
  static const String homeName = 'home';

  static const String visits = '/visits';
  static const String visitsName = 'visits';

  static const String referrals = '/referrals';
  static const String referralsName = 'referrals';

  static const String reports = '/reports';
  static const String reportsName = 'reports';

  static const String more = '/more';
  static const String moreName = 'more';

  // School and AWC masters, under More (docs/35_PHASE_1_5_PLAN.md §15).
  static const String schools = '/more/schools';
  static const String schoolsName = 'schools';
  static const String schoolAdd = '/more/schools/add';
  static const String schoolAddName = 'school-add';
  static const String schoolDuplicates = '/more/schools/duplicates';
  static const String schoolDuplicatesName = 'school-duplicates';
  static const String schoolDetailName = 'school-detail';
  static const String schoolEditName = 'school-edit';
  static String schoolDetail(String id) => '$schools/$id';
  static String schoolEdit(String id) => '$schools/$id/edit';

  static const String awcs = '/more/awcs';
  static const String awcsName = 'awcs';
  static const String awcAdd = '/more/awcs/add';
  static const String awcAddName = 'awc-add';
  static const String awcDuplicates = '/more/awcs/duplicates';
  static const String awcDuplicatesName = 'awc-duplicates';
  static const String awcDetailName = 'awc-detail';
  static const String awcEditName = 'awc-edit';
  static String awcDetail(String id) => '$awcs/$id';
  static String awcEdit(String id) => '$awcs/$id/edit';
}
