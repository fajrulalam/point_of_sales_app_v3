import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';

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
      name: (data['fullName'] ?? data['name'] ?? '').toString(),
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      memberId: data['memberId']?.toString(),
      points: MemberProgramValues.intValue(data['points']),
      createdAt: MemberProgramValues.dateValue(data['createdAt']),
      category: (data['category'] ?? '').toString(),
      asrama: (data['asrama'] ?? '').toString(),
      dateOfBirth: (data['dateOfBirth'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      faculty: (data['faculty'] ?? '').toString(),
      gender: (data['gender'] ?? '').toString(),
      institution: (data['institution'] ?? '').toString(),
      major: (data['major'] ?? '').toString(),
      residence: (data['residence'] ?? '').toString(),
      unitEducation: (data['unitEducation'] ?? '').toString(),
      workLocation: (data['workLocation'] ?? '').toString(),
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
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phoneNumber: (map['phoneNumber'] ?? '').toString(),
      memberId: map['memberId']?.toString(),
      points: MemberProgramValues.intValue(map['points']),
      createdAt: MemberProgramValues.dateValue(map['createdAt']),
      category: (map['category'] ?? '').toString(),
      asrama: (map['asrama'] ?? '').toString(),
      dateOfBirth: (map['dateOfBirth'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      faculty: (map['faculty'] ?? '').toString(),
      gender: (map['gender'] ?? '').toString(),
      institution: (map['institution'] ?? '').toString(),
      major: (map['major'] ?? '').toString(),
      residence: (map['residence'] ?? '').toString(),
      unitEducation: (map['unitEducation'] ?? '').toString(),
      workLocation: (map['workLocation'] ?? '').toString(),
    );
  }
}
