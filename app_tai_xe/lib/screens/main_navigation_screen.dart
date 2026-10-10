import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import 'home_driver_screen.dart';
import 'map_screen.dart';
import 'dispatch_supervisor_screen.dart';
import 'login_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentRoot = 2; // 0: GPS, 1: Driver, 2: Management
  int _activeManagementTab = 0;
  int _usersSubTab = 0; // 0: Danh sách Tài khoản, 1: Cấu hình Vai trò & Quyền

  @override
  void initState() {
    super.initState();
    // Mặc định khi vào app luôn luôn mở màn hình Tổng quan & Báo cáo Tuân thủ (_currentRoot = 2, _activeManagementTab = 0)
    _currentRoot = 2;
    _activeManagementTab = 0;

    final state = context.read<AppState>();
    final roles = state.userRoles.map((r) => r.toLowerCase()).toList();
    final username = (state.currentUsername ?? '').trim().toLowerCase();

    // Chỉ chuyển sang màn hình Nghiệp vụ Tài xế khi tài khoản là tài xế thuần túy (không phải admin, manager, dispatcher)
    if (roles.contains('driver') && !roles.contains('admin') && !roles.contains('manager') && !roles.contains('dispatcher') && username != 'admin') {
      _currentRoot = 1;
      state.setRole(UserRole.driver);
    } else {
      _currentRoot = 2;
      _activeManagementTab = 0;
      state.setRole(UserRole.manager);
    }
  }

  final List<String> _managementTitles = const [
    "Tổng Quan & Báo Cáo Tuân Thủ",
    "Quản Lý Đơn Hàng Vận Tải",
    "Quản Lý Đội Xe & Phương Tiện",
    "Quản Lý Tài Khoản & Phân Quyền",
    "Cây Dầu & Đối Soát Nhiên Liệu",
    "Danh Mục Sản Phẩm & Vật Liệu",
  ];

  String _getAppTitle() {
    if (_currentRoot == 0) return "Bản Đồ Giám Sát GPS";
    if (_currentRoot == 1) return "Nghiệp Vụ Tài Xế Giao Hàng";
    return _managementTitles[_activeManagementTab];
  }

  void _onSelectRoot(int rootIndex) {
    final state = context.read<AppState>();
    setState(() {
      _currentRoot = rootIndex;
      if (rootIndex == 1) {
        state.setRole(UserRole.driver);
      } else if (rootIndex == 2) {
        state.setRole(UserRole.manager);
      }
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _onSelectManagementTab(int tabIndex) {
    final state = context.read<AppState>();
    setState(() {
      _currentRoot = 2;
      _activeManagementTab = tabIndex;
      state.setRole(UserRole.manager);
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _onLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final media = MediaQuery.of(context);
    final width = media.size.width;
    // Mobile: màn hình hẹp (< 768px), Tablet/iPad/Desktop: >= 768px luôn ưu tiên ghim sidebar cố định
    final isMobile = width < 768;

    final sidebarContent = _buildSidebarContent(state);

    if (!isMobile) {
      // Bố cục Desktop / iPad / Tablet: Sidebar luôn hiển thị cố định bên trái
      return Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            SizedBox(
              width: width >= 1200 ? 300 : 270,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF10172A), // Màu Slate đậm hơn Header (0xFF1E293B / BlueGrey 900)
                  border: Border(
                    right: BorderSide(color: Color(0xFF1E293B), width: 1), // Viền tối đồng bộ màu, không còn vệt trắng
                  ),
                ),
                child: sidebarContent,
              ),
            ),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    _getAppTitle(),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey.shade900),
                  ),
                  actions: [
                    if (_currentRoot == 2 && _activeManagementTab == 3)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: _buildUserSubTabSwitch(),
                      ),
                  ],
                  backgroundColor: Colors.transparent, // Không dùng màu background
                  foregroundColor: Colors.blueGrey.shade900,
                  automaticallyImplyLeading: false,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(
                      color: Colors.grey.shade300,
                      height: 1,
                    ),
                  ),
                ),
                body: _buildCurrentBody(),
              ),
            ),
          ],
        ),
      );
    }

    // Bố cục Mobile: Dùng Drawer phủ đè
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu, color: Colors.blueGrey.shade900),
          tooltip: "Mở menu chức năng",
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Text(
          _getAppTitle(),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey.shade900),
        ),
        actions: [
          if (_currentRoot == 2 && _activeManagementTab == 3)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildUserSubTabSwitch(isCompact: true),
            ),
        ],
        backgroundColor: Colors.transparent, // Không dùng màu background
        foregroundColor: Colors.blueGrey.shade900,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade300,
            height: 1,
          ),
        ),
      ),
      drawer: Drawer(
        width: width * 0.85,
        backgroundColor: Colors.white,
        elevation: 0,
        child: sidebarContent,
      ),
      body: _buildCurrentBody(),
    );
  }

  Widget _buildSidebarContent(AppState state) {
    return Container(
      color: const Color(0xFF0F172A), // Nền Sidebar tối đậm Slate 900 (đậm hơn Header 0xFF1E293B)
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E293B), width: 1), // Đường kẻ tối tiệp màu, không viền trắng
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: Colors.white12,
                          child: const Icon(Icons.local_shipping, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.currentFullName ?? "Người dùng",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "@${state.currentUsername ?? 'admin'}",
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSectionHeader("ĐIỀU HÀNH & TÀI XẾ"),
                _buildDrawerItem(
                  isSelected: _currentRoot == 0,
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map,
                  title: "Bản đồ Giám sát GPS",
                  subtitle: "Theo dõi vị trí xe thời gian thực",
                  onTap: () => _onSelectRoot(0),
                ),
                _buildDrawerItem(
                  isSelected: _currentRoot == 1,
                  icon: Icons.local_shipping_outlined,
                  activeIcon: Icons.local_shipping,
                  title: "Nghiệp vụ Tài xế",
                  subtitle: "Kiểm tra xe, bấm mốc giờ, phiếu cân",
                  onTap: () => _onSelectRoot(1),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  child: Divider(color: Color(0xFF1E293B), height: 1),
                ),
                _buildSectionHeader("HỆ THỐNG QUẢN TRỊ DỰ ÁN"),
                _buildDrawerItem(
                  isSelected: _currentRoot == 2 && _activeManagementTab == 0,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  title: "Tổng quan & Báo cáo",
                  subtitle: "Chỉ số vận hành, tỷ lệ tuân thủ",
                  onTap: () => _onSelectManagementTab(0),
                ),
                _buildDrawerItem(
                  isSelected: _currentRoot == 2 && _activeManagementTab == 1,
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment,
                  title: "Đơn hàng vận tải",
                  subtitle: "Danh sách đơn, tuyến đường giao",
                  onTap: () => _onSelectManagementTab(1),
                ),
                _buildDrawerItem(
                  isSelected: _currentRoot == 2 && _activeManagementTab == 2,
                  icon: Icons.directions_car_outlined,
                  activeIcon: Icons.directions_car,
                  title: "Đội xe & Tài xế",
                  subtitle: "Xe nội bộ, xe thuê ngoài, phân bổ",
                  onTap: () => _onSelectManagementTab(2),
                ),
                _buildDrawerItem(
                  isSelected: _currentRoot == 2 && _activeManagementTab == 4,
                  icon: Icons.ev_station_outlined,
                  activeIcon: Icons.ev_station,
                  title: "Cây dầu & Đối soát",
                  subtitle: "Định mức tiêu hao, công nợ cấp phát",
                  onTap: () => _onSelectManagementTab(4),
                ),
                _buildDrawerItem(
                  isSelected: _currentRoot == 2 && _activeManagementTab == 5,
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  title: "Sản phẩm & Vật liệu",
                  subtitle: "Xi măng rời, xi măng bao, phụ gia",
                  onTap: () => _onSelectManagementTab(5),
                ),
                if (state.currentUsername == 'admin' || state.userRoles.contains('admin'))
                  _buildDrawerItem(
                    isSelected: _currentRoot == 2 && _activeManagementTab == 3,
                    icon: Icons.admin_panel_settings_outlined,
                    activeIcon: Icons.admin_panel_settings,
                    title: "Tài khoản & Phân quyền",
                    subtitle: "Quản lý nhân viên, Dynamic RBAC",
                    onTap: () => _onSelectManagementTab(3),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Text(
                    "Công ty CP TM Xi Măng Sao Mai",
                    style: TextStyle(
                      color: Colors.amber.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Phiên bản hệ thống: v2.4.0 Dark Sidebar",
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      side: BorderSide(color: Colors.red.shade400.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.exit_to_app, size: 20),
                    label: const Text("Đăng xuất tài khoản", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _onLogout,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentBody() {
    if (_currentRoot == 0) {
      return const MapScreen();
    } else if (_currentRoot == 1) {
      return const HomeDriverScreen();
    } else {
      return DispatchSupervisorScreen(
        activeTab: _activeManagementTab,
        usersSubTab: _usersSubTab,
        onTabChanged: (index) {
          setState(() {
            _activeManagementTab = index;
          });
        },
      );
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.blueGrey,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required bool isSelected,
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          leading: Icon(
            isSelected ? activeIcon : icon,
            color: isSelected ? Colors.amber : Colors.blueGrey.shade400,
            size: 22,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 13.5,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.amber.shade200 : Colors.white38,
            ),
          ),
          selected: isSelected,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildUserSubTabSwitch({bool isCompact = false}) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSwitchItem(
            index: 0,
            icon: Icons.person,
            label: "Danh sách Tài khoản",
            isCompact: isCompact,
          ),
          const SizedBox(width: 2),
          _buildSwitchItem(
            index: 1,
            icon: Icons.verified_user,
            label: "Cấu hình Vai trò & Quyền",
            isCompact: isCompact,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isCompact,
  }) {
    final isSelected = _usersSubTab == index;
    return InkWell(
      onTap: () {
        if (_usersSubTab != index) {
          setState(() {
            _usersSubTab = index;
          });
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.blue.shade800 : Colors.blueGrey.shade600,
            ),
            if (!isCompact) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.blue.shade900 : Colors.blueGrey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
