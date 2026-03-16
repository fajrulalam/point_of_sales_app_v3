class Member {
  final String id;
  final String name; // maps from fullName
  final String phoneNumber;
  final String? memberId;
  final int points;
  final DateTime? createdAt;
  
  // New fields
  final String category;
  final String asrama;
  final String dateOfBirth;
  final String email;
  final String faculty;
  final String gender;
  final String institution;
  final String major;
  final String residence;
  final String unitEducation;
  final String workLocation;

  Member({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.memberId,
    this.points = 0,
    this.createdAt,
    this.category = '',
    this.asrama = '',
    this.dateOfBirth = '',
    this.email = '',
    this.faculty = '',
    this.gender = '',
    this.institution = '',
    this.major = '',
    this.residence = '',
    this.unitEducation = '',
    this.workLocation = '',
  });

  factory Member.fromFirestore(String id, Map<String, dynamic> data) {
    return Member(
      id: id,
      name: data['fullName'] ?? (data['name'] ?? ''),
      phoneNumber: data['phoneNumber'] ?? '',
      memberId: data['memberId'],
      points: data['points'] ?? 0,
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as dynamic).toDate() 
          : null,
      category: data['category'] ?? '',
      asrama: data['asrama'] ?? '',
      dateOfBirth: data['dateOfBirth'] ?? '',
      email: data['email'] ?? '',
      faculty: data['faculty'] ?? '',
      gender: data['gender'] ?? '',
      institution: data['institution'] ?? '',
      major: data['major'] ?? '',
      residence: data['residence'] ?? '',
      unitEducation: data['unitEducation'] ?? '',
      workLocation: data['workLocation'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'memberId': memberId,
      'points': points,
      'createdAt': createdAt?.toIso8601String(),
      'category': category,
      'asrama': asrama,
      'dateOfBirth': dateOfBirth,
      'email': email,
      'faculty': faculty,
      'gender': gender,
      'institution': institution,
      'major': major,
      'residence': residence,
      'unitEducation': unitEducation,
      'workLocation': workLocation,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'],
      name: map['name'],
      phoneNumber: map['phoneNumber'],
      memberId: map['memberId'],
      points: map['points'] ?? 0,
      createdAt: map['createdAt'] != null 
          ? DateTime.parse(map['createdAt']) 
          : null,
      category: map['category'] ?? '',
      asrama: map['asrama'] ?? '',
      dateOfBirth: map['dateOfBirth'] ?? '',
      email: map['email'] ?? '',
      faculty: map['faculty'] ?? '',
      gender: map['gender'] ?? '',
      institution: map['institution'] ?? '',
      major: map['major'] ?? '',
      residence: map['residence'] ?? '',
      unitEducation: map['unitEducation'] ?? '',
      workLocation: map['workLocation'] ?? '',
    );
  }
}
