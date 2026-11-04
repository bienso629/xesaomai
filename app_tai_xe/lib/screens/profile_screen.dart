import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';

/// Màn hình Hồ sơ cá nhân: xem/sửa thông tin cá nhân và đổi mật khẩu.
/// Quy chuẩn style: rounded-sm 4px, nút chính 36px, nút phụ 32px, màu blue.shade800.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ---- Form thông tin cá nhân ----
  final _profileFormKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // ---- Form đổi mật khẩu ----
  final _passwordFormKey = GlobalKey<FormState>();
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _savingProfile = false;
  bool _savingPassword = false;
  String? _pendingAvatarUrl;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _fullNameCtrl.text = state.currentFullName ?? '';
    _phoneCtrl.text = state.currentPhone ?? '';
    _emailCtrl.text = state.currentEmail ?? '';
    _addressCtrl.text = state.currentAddress ?? '';
    // Tải hồ sơ mới nhất từ server (GET /auth/me) để tránh dữ liệu cũ
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await state.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _fullNameCtrl.text = state.currentFullName ?? '';
        _phoneCtrl.text = state.currentPhone ?? '';
        _emailCtrl.text = state.currentEmail ?? '';
        _addressCtrl.text = state.currentAddress ?? '';
      });
    });
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ---- Chọn ảnh đại diện từ thư viện ----
  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (picked == null) return;
      final res = await AdminService.uploadImage(picked.path);
      if (!mounted) return;
      if (res['success'] == true && (res['url'] ?? '').toString().isNotEmpty) {
        setState(() {
          _pendingAvatarUrl = res['url'].toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chọn ảnh đại diện. Nhấn "Lưu thay đổi" để áp dụng.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((res['message'] ?? 'Không thể tải ảnh lên.').toString()),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  // ---- Lưu thông tin cá nhân ----
  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    final state = context.read<AppState>();
    final error = await state.updateMyProfile(
      fullName: _fullNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      avatarUrl: _pendingAvatarUrl,
    );
    if (!mounted) return;
    setState(() {
      _savingProfile = false;
      if (error == null) _pendingAvatarUrl = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Đã lưu thông tin cá nhân thành công.'),
        backgroundColor: error == null ? Colors.green : Colors.red.shade700,
      ),
    );
  }

  // ---- Đổi mật khẩu ----
  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    final res = await AdminService.changeMyPassword(
      currentPassword: _currentPasswordCtrl.text,
      newPassword: _newPasswordCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _savingPassword = false;
      if (res['success'] == true) {
        _currentPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((res['message'] ?? '').toString()),
        backgroundColor: res['success'] == true ? Colors.green : Colors.red.shade700,
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  // ---- Khu vực avatar + nút Edit nhỏ bên dưới ----
  Widget _buildAvatarSection(AppState state) {
    final url = (_pendingAvatarUrl ?? state.currentAvatarUrl ?? '').trim();
    final hasUrl = url.isNotEmpty;
    final fullUrl = hasUrl
        ? (url.startsWith('http://') || url.startsWith('https://')
            ? url
            : '${ApiConfig.host}${url.startsWith('/') ? '' : '/'}$url')
        : url;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue.shade800, width: 2),
              ),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.blue.shade50,
                child: ClipOval(
                  child: hasUrl
                      ? Image.network(
                          fullUrl,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 88,
                            height: 88,
                            color: Colors.blue.shade50,
                            alignment: Alignment.center,
                            child: Text(
                              _initials(state.currentFullName ?? state.currentUsername ?? '?'),
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          width: 88,
                          height: 88,
                          alignment: Alignment.center,
                          child: Text(
                            _initials(state.currentFullName ?? state.currentUsername ?? '?'),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // Nút Edit nhỏ chồng góc dưới-phải của avatar
            Positioned(
              right: -2,
              bottom: -2,
              child: Tooltip(
                message: 'Đổi ảnh đại diện',
                child: Material(
                  color: Colors.blue.shade800,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          state.currentFullName ?? 'Người dùng',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          '@${state.currentUsername ?? ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade300, height: 1),
        ),
      ),
      body: Container(
        color: const Color(0xFFF1F5F9),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ---- Thẻ thông tin cá nhân ----
                _buildSectionCard(
                  child: Column(
                    children: [
                      _buildAvatarSection(state),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Thông tin cá nhân',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Form(
                        key: _profileFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _fullNameCtrl,
                              decoration: const InputDecoration(labelText: 'Họ và tên'),
                              textInputAction: TextInputAction.next,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Vui lòng nhập họ tên' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(labelText: 'Số điện thoại'),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Vui lòng nhập số điện thoại'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(labelText: 'Email'),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null; // Email không bắt buộc
                                final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                if (!re.hasMatch(t)) return 'Email không hợp lệ';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(labelText: 'Địa chỉ'),
                              textInputAction: TextInputAction.done,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _savingProfile ? null : _saveProfile,
                          icon: _savingProfile
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 16),
                          label: Text(_savingProfile ? 'Đang lưu...' : 'Lưu thay đổi'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ---- Thẻ đổi mật khẩu ----
                _buildSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đổi mật khẩu',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Form(
                        key: _passwordFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _currentPasswordCtrl,
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu hiện tại',
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureCurrent
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                      size: 18),
                                  onPressed: () =>
                                      setState(() => _obscureCurrent = !_obscureCurrent),
                                ),
                              ),
                              obscureText: _obscureCurrent,
                              textInputAction: TextInputAction.next,
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Vui lòng nhập mật khẩu hiện tại'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _newPasswordCtrl,
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu mới',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                      _obscureNew ? Icons.visibility_off : Icons.visibility,
                                      size: 18),
                                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                                ),
                              ),
                              obscureText: _obscureNew,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu mới';
                                if (v.length < 6) return 'Mật khẩu mới tối thiểu 6 ký tự';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordCtrl,
                              decoration: InputDecoration(
                                labelText: 'Nhập lại mật khẩu mới',
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                      size: 18),
                                  onPressed: () =>
                                      setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Vui lòng nhập lại mật khẩu mới';
                                if (v != _newPasswordCtrl.text) return 'Mật khẩu nhập lại không khớp';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _savingPassword ? null : _changePassword,
                          icon: _savingPassword
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.lock_reset, size: 16),
                          label: Text(_savingPassword ? 'Đang xử lý...' : 'Đổi mật khẩu'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
