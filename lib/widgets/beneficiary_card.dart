import 'package:flutter/material.dart';
import '../models/beneficiary.dart';

class BeneficiaryCard extends StatelessWidget {
  final Beneficiary beneficiary;
  final VoidCallback onTap;

  const BeneficiaryCard({super.key, required this.beneficiary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(right: BorderSide(color: Theme.of(context).primaryColor, width: 6)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(beneficiary.displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (beneficiary.birthInfo.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(beneficiary.birthInfo, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      _buildBadge(beneficiary.program ?? 'عام', Colors.blue),
                      _buildBadge(beneficiary.address ?? 'غير محدد', Colors.green),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Theme.of(context).primaryColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 13, color: color.shade700)),
    );
  }
}
