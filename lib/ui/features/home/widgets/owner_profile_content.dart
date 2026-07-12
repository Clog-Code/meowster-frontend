import 'package:flutter/material.dart';

import '../../../../domain/models/owner_profile.dart';
import '../../../core/pet_theme.dart';

class OwnerProfileContent extends StatefulWidget {
  const OwnerProfileContent({this.onSaved, super.key});

  final ValueChanged<OwnerProfile>? onSaved;

  @override
  State<OwnerProfileContent> createState() => _OwnerProfileContentState();
}

class _OwnerProfileContentState extends State<OwnerProfileContent> {
  String _name = 'Dickson Lai';
  String _phone = '+65 8xxx 9460';
  String _address = '14000 Bukit Mertajam, Pulau Pinang';
  bool _editing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _name);
    _phoneCtrl = TextEditingController(text: _phone);
    _addressCtrl = TextEditingController(text: _address);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    if (_editing) {
      setState(() {
        _name = _nameCtrl.text;
        _phone = _phoneCtrl.text;
        _address = _addressCtrl.text;
        _editing = false;
      });
      widget.onSaved?.call(
        OwnerProfile(name: _name, phone: _phone, address: _address),
      );
    } else {
      setState(() {
        _nameCtrl.text = _name;
        _phoneCtrl.text = _phone;
        _addressCtrl.text = _address;
        _editing = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: PetTheme.aqua.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(48),
              ),
              child: Center(
                child: Text(
                  _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: PetTheme.aqua,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Owner Profile',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text(
                    _name,
                    style: TextStyle(color: PetTheme.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _toggleEdit,
              icon: Icon(
                _editing ? Icons.check : Icons.edit_outlined,
                size: 20,
                color: PetTheme.aqua,
              ),
              tooltip: _editing ? 'Save' : 'Edit owner profile',
            ),
          ],
        ),
        SizedBox(height: 16),
        _InfoField(
          icon: Icons.person_outline,
          value: _name,
          controller: _nameCtrl,
          editing: _editing,
        ),
        SizedBox(height: 10),
        _InfoField(
          icon: Icons.phone_outlined,
          value: _phone,
          controller: _phoneCtrl,
          editing: _editing,
        ),
        SizedBox(height: 10),
        _InfoField(
          icon: Icons.location_on_outlined,
          value: _address,
          controller: _addressCtrl,
          editing: _editing,
        ),
      ],
    );
  }
}

class _InfoField extends StatelessWidget {
  const _InfoField({
    required this.icon,
    required this.value,
    required this.controller,
    required this.editing,
  });

  final IconData icon;
  final String value;
  final TextEditingController controller;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: editing ? 4 : 10),
      decoration: BoxDecoration(
        color: PetTheme.panelSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: PetTheme.aqua),
          SizedBox(width: 10),
          Expanded(
            child: editing
                ? TextField(
                    controller: controller,
                    style: TextStyle(color: PetTheme.ivory, fontSize: 14),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: PetTheme.muted, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
