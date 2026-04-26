import 'dart:io';
import 'package:flutter/material.dart';
import '../models/beneficiary.dart';

class BeneficiaryCard extends StatelessWidget {
  final Beneficiary beneficiary;
  final VoidCallback onTap;

  const BeneficiaryCard({super.key, required this.beneficiary, required this.onTap});

  static const _statusColors = {
    'منتهية ومشغولة':    Color(0xFF00897B),
    'منتهية غير مشغولة': Color(0xFF558B2F),
    'على مستوى الاعمدة': Color(0xFF1565C0),
    'في طور الانجاز':    Color(0xFFE65100),
  };

  static const _statusIcons = {
    'منتهية ومشغولة':    Icons.home_rounded,
    'منتهية غير مشغولة': Icons.home_outlined,
    'على مستوى الاعمدة': Icons.foundation_rounded,
    'في طور الانجاز':    Icons.construction_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[beneficiary.status] ?? const Color(0xFF546E7A);
    final icon  = _statusIcons[beneficiary.status]  ?? Icons.home_rounded;
    final hasImage = beneficiary.imagePath != null &&
        beneficiary.imagePath!.isNotEmpty &&
        File(beneficiary.imagePath!).existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shadowColor: color.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(right: BorderSide(color: color, width: 5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            // صورة أو أيقونة الحالة
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: color.withOpacity(0.1),
              ),
              child: hasImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(beneficiary.imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, color: color, size: 26),
                      ))
                  : Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 12),

            // المعلومات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        beneficiary.displayName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasImage)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt,
                                size: 11, color: Colors.green),
                            SizedBox(width: 2),
                            Text('صورة',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.green)),
                          ],
                        ),
                      ),
                  ]),

                  if (beneficiary.birthInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        beneficiary.birthInfo,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  const SizedBox(height: 6),
                  Row(children: [
                    _Badge(beneficiary.program ?? 'عام',
                        Colors.blue, Icons.folder_outlined),
                    const SizedBox(width: 6),
                    _Badge(beneficiary.address ?? 'غير محدد',
                        Colors.orange, Icons.location_on_outlined),
                    if (beneficiary.done == 1) ...[
                      const SizedBox(width: 6),
                      _Badge(beneficiary.status, color,  icon, small: true),
                    ]
                  ]),

                  // مؤشرات الشبكات للمحصاة
                  if (beneficiary.done == 1) ...[
                    const SizedBox(height: 5),
                    _NetworkRow(beneficiary: beneficiary),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 6),
            Icon(Icons.chevron_left_rounded,
                color: Colors.grey.shade400, size: 22),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final bool small;

  const _Badge(this.text, this.color, this.icon, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: small ? 10 : 11,
            color: color.withOpacity(0.8)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
              fontSize: small ? 10 : 11,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  final Beneficiary beneficiary;
  const _NetworkRow({required this.beneficiary});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.bolt,          'كهرباء', beneficiary.electricity),
      (Icons.local_fire_department, 'غاز', beneficiary.gas),
      (Icons.water_drop,    'مياه',   beneficiary.water),
      (Icons.cleaning_services, 'تطهير', beneficiary.sewage),
    ];
    return Row(
      children: items.map((item) {
        final active = item.$3 == 1;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: item.$2,
            child: Icon(
              item.$1,
              size: 14,
              color: active ? Colors.amber.shade700 : Colors.grey.shade300,
            ),
          ),
        );
      }).toList(),
    );
  }
}
