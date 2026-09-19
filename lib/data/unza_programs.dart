/// University of Zambia — schools and their undergraduate programmes.
///
/// ⚠️ BEST-EFFORT SEED — compiled from general knowledge, NOT the official
/// prospectus. Please verify against the current UNZA prospectus and edit this
/// map freely (add/rename/remove). Students whose school or programme isn't
/// listed can choose "Other (not listed)" at signup and type it in, so an
/// incomplete list never blocks anyone.
///
/// Used by the signup screen for cascading School → Programme dropdowns, and it
/// keeps the profile's school/programme structured (which feeds ZChat AI's
/// per-student context).
library;

const String kOtherOption = 'Other (not listed)';

/// School name → list of programmes offered under it.
const Map<String, List<String>> kUnzaSchools = {
  'School of Natural Sciences': [
    'BSc Computer Science',
    'BSc Mathematics',
    'BSc Statistics',
    'BSc Physics',
    'BSc Chemistry',
    'BSc Biology',
    'BSc Geology',
    'BSc Biological Sciences',
    'BSc Environmental Science',
  ],
  'School of Engineering': [
    'BEng Civil Engineering',
    'BEng Electrical & Electronic Engineering',
    'BEng Electronics & Telecommunications Engineering',
    'BEng Computer Engineering',
    'BEng Mechanical Engineering',
    'BEng Agricultural Engineering',
    'BEng Geomatic Engineering',
    'BEng Surveying',
  ],
  'School of Mines': [
    'BSc Mining Engineering',
    'BSc Metallurgy & Mineral Processing',
    'BSc Exploration Geology',
    'BSc Chemical Engineering',
  ],
  'School of Agricultural Sciences': [
    'BSc Agricultural Sciences',
    'BSc Agricultural Economics',
    'BSc Agribusiness',
    'BSc Food Science & Technology',
    'BSc Animal Science',
    'BSc Crop Science',
    'BSc Soil Science',
  ],
  'School of Veterinary Medicine': [
    'Bachelor of Veterinary Medicine (BVM)',
  ],
  'School of Medicine': [
    'Bachelor of Medicine & Bachelor of Surgery (MBChB)',
    'Bachelor of Pharmacy (BPharm)',
    'Bachelor of Dental Surgery',
    'Bachelor of Biomedical Sciences',
    'Bachelor of Physiotherapy',
  ],
  'School of Health Sciences': [
    'BSc Radiography',
    'BSc Physiotherapy',
    'BSc Biomedical Sciences',
    'BSc Environmental Health',
  ],
  'School of Public Health': [
    'Bachelor of Public Health',
    'BSc Environmental Health',
  ],
  'School of Nursing Sciences': [
    'BSc Nursing (BScN)',
    'Bachelor of Midwifery',
  ],
  'School of Education': [
    'Bachelor of Education (Primary)',
    'Bachelor of Education (Secondary)',
    'Bachelor of Arts with Education',
    'Bachelor of Science with Education',
    'Bachelor of Education (Special Education)',
    'Bachelor of Education (Educational Psychology)',
    'Bachelor of Library & Information Science',
  ],
  'School of Humanities & Social Sciences': [
    'Bachelor of Arts (General)',
    'Bachelor of Arts in Economics',
    'Bachelor of Arts in Development Studies',
    'Bachelor of Arts in Public Administration',
    'Bachelor of Arts in Political Science',
    'Bachelor of Arts in Psychology',
    'Bachelor of Arts in Mass Communication',
    'Bachelor of Social Work',
    'Bachelor of Arts in Demography',
    'Bachelor of Gender Studies',
    'Bachelor of Arts in History',
    'Bachelor of Arts in Literature',
  ],
  'School of Law': [
    'Bachelor of Laws (LLB)',
  ],
  'School of Business': [
    'Bachelor of Business Administration',
    'Bachelor of Accountancy',
    'Bachelor of Commerce',
    'Bachelor of Banking & Finance',
    'Bachelor of Marketing',
  ],
};

/// School names for the first dropdown (plus the "Other" escape hatch).
List<String> get unzaSchoolNames => [...kUnzaSchools.keys, kOtherOption];

/// Programmes for a chosen school (plus "Other"); empty list yields just "Other".
List<String> programmesFor(String? school) {
  final progs = (school == null || school == kOtherOption) ? const <String>[] : (kUnzaSchools[school] ?? const []);
  return [...progs, kOtherOption];
}
