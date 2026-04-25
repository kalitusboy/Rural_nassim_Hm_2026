
class Beneficiary {
  int? id;
  String firstName;
  String lastName;
  String? name;
  String? birthDate;
  String? birthPlace;
  String? address;
  String? program;
  int done;
  int electricity;
  int gas;
  int water;
  int sewage;
  String status;
  String? imagePath;
  String? imageFileName;
  DateTime? createdAt;
  DateTime? updatedAt;

  Beneficiary({
    this.id,
    required this.firstName,
    required this.lastName,
    this.name,
    this.birthDate,
    this.birthPlace,
    this.address,
    this.program,
    this.done = 0,
    this.electricity = 0,
    this.gas = 0,
    this.water = 0,
    this.sewage = 0,
    this.status = 'في طور الانجاز',
    this.imagePath,
    this.imageFileName,
    this.createdAt,
    this.updatedAt,
  });

  factory Beneficiary.fromMap(Map<String, dynamic> map) {
    return Beneficiary(
      id: map['id'] as int?,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      name: map['full_name'] as String?,
      birthDate: map['birth_date'] as String?,
      birthPlace: map['birth_place'] as String?,
      address: map['address'] as String?,
      program: map['program'] as String?,
      done: map['done'] as int? ?? 0,
      electricity: map['electricity'] as int? ?? 0,
      gas: map['gas'] as int? ?? 0,
      water: map['water'] as int? ?? 0,
      sewage: map['sewage'] as int? ?? 0,
      status: map['status'] as String? ?? 'في طور الانجاز',
      imagePath: map['image_path'] as String?,
      imageFileName: map['image_file_name'] as String?,
      createdAt: map['created_at'] != null ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int) : null,
      updatedAt: map['updated_at'] != null ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': name,
      'birth_date': birthDate,
      'birth_place': birthPlace,
      'address': address,
      'program': program,
      'done': done,
      'electricity': electricity,
      'gas': gas,
      'water': water,
      'sewage': sewage,
      'status': status,
      'image_path': imagePath,
      'image_file_name': imageFileName,
      'created_at': createdAt?.millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory Beneficiary.fromExcelRow(Map<String, dynamic> row) {
    String getValue(List<String> keys) {
      for (var key in keys) {
        if (row.containsKey(key) && row[key] != null) return row[key].toString().trim();
      }
      return '';
    }
    return Beneficiary(
      firstName: getValue(['الاسم الأول', 'firstName', 'first_name']),
      lastName: getValue(['اللقب', 'lastName', 'last_name']),
      name: getValue(['الاسم', 'name', 'full_name']),
      birthDate: getValue(['تاريخ الميلاد', 'birthDate', 'birth_date']),
      birthPlace: getValue(['مكان الميلاد', 'birthPlace', 'birth_place']),
      address: getValue(['العنوان', 'address']),
      program: getValue(['البرنامج', 'program']) != '' ? getValue(['البرنامج', 'program']) : 'عام',
    );
  }

  String get displayName {
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();
    }
    return name ?? 'مستفيد';
  }

  String get birthInfo {
    final parts = <String>[];
    if (birthDate != null && birthDate!.isNotEmpty) parts.add('📅 $birthDate');
    if (birthPlace != null && birthPlace!.isNotEmpty) parts.add('📍 $birthPlace');
    return parts.join(' | ');
  }

  String generateImageFileName() {
    String normalize(String text) {
      return text
          .replaceAll(RegExp(r'[\/\\?%*:|"<>]'), '_')
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
    }
    final parts = [
      normalize(program ?? 'عام'),
      normalize(address ?? 'غير_محدد'),
      normalize(displayName),
      normalize([birthDate ?? '', birthPlace ?? ''].where((s) => s.isNotEmpty).join('_')),
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-'),
    ];
    return '${parts.where((s) => s.isNotEmpty).join('__')}.jpg';
  }

  Beneficiary copyWith({
    int? id, String? firstName, String? lastName, String? name,
    String? birthDate, String? birthPlace, String? address, String? program,
    int? done, int? electricity, int? gas, int? water, int? sewage,
    String? status, String? imagePath, String? imageFileName,
  }) {
    return Beneficiary(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      birthPlace: birthPlace ?? this.birthPlace,
      address: address ?? this.address,
      program: program ?? this.program,
      done: done ?? this.done,
      electricity: electricity ?? this.electricity,
      gas: gas ?? this.gas,
      water: water ?? this.water,
      sewage: sewage ?? this.sewage,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageFileName: imageFileName ?? this.imageFileName,
    );
  }
}
