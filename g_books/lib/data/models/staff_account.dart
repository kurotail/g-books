/// 後台人員角色。目前僅 [admin] 可編輯古蹟設定，[teacher] 為占位（功能開發中）。
enum StaffRole { teacher, admin }

/// 教師 / 管理者帳號。現階段以本機 mock 清單比對，之後換成後端登入回傳。
class StaffAccount {
  final String username;
  final String password;
  final String displayName;
  final StaffRole role;

  const StaffAccount({
    required this.username,
    required this.password,
    required this.displayName,
    required this.role,
  });
}
