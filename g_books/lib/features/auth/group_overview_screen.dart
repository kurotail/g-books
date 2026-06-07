import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../core/widgets/step_indicator.dart';
import '../../data/models/user_model.dart';
import '../../state/app_state.dart';
import 'upload_avatar_screen.dart';

/// 小組總攬。兩種用途，依 [AppState.isSetupComplete] 區分：
/// - 設定流程最後一步（尚未完成設定）：顯示步驟列，底部「進入遊戲」完成設定並進古蹟選擇。
/// - 檢視古蹟時從面板進入（已完成設定）：不顯示步驟列，底部「完成」返回上一頁。
/// 兩種用途都可點組員卡片進入上傳畫面設定該組員頭像（人數多可左右滑動、少人置中）。
class GroupOverviewScreen extends StatelessWidget {
  const GroupOverviewScreen({super.key});

  static const _steps = ['登陸帳號', '小組頭像', '小組命名', '小組建立成功'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final group = state.currentGroup;
    final members = state.groupMembers;
    final editMode = state.isSetupComplete;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(context, editMode);
      },
      child: ParchmentScaffold(
        child: Stack(
          children: [
            // 左上：小組頭像 + 名稱
            Positioned(
              top: 28,
              left: 40,
              child: _GroupHeader(
                name: group?.name ?? '',
                avatarUrl: group?.avatarUrl,
              ),
            ),
            // 右側步驟列（僅設定流程顯示）
            if (!editMode)
              const Positioned(
                right: 36,
                top: 0,
                bottom: 0,
                width: 150,
                child: Center(
                  child: StepIndicator(steps: _steps, currentStep: 3),
                ),
              ),
            // 右上：返回（往畫面內側收一點，避免太靠近螢幕邊緣不好點）
            Positioned(
              top: 36,
              right: 64,
              child: GestureDetector(
                onTap: () => _back(context, editMode),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 24,
                  color: Color(0xFF6A6A6A),
                ),
              ),
            ),
            // 主內容：提示 + 組員卡片
            Positioned(
              left: 40,
              right: 190,
              top: 150,
              bottom: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '點擊組員頭像即可編輯！',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.labelText,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        height: 212,
                        child: _memberStrip(context, members),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 右下：進入遊戲 / 完成
            Positioned(
              right: 40,
              bottom: 28,
              child: _bottomButton(context, editMode),
            ),
          ],
        ),
      ),
    );
  }

  /// 返回上一步：設定中回小組命名頁；檢視古蹟進來則 pop 回上一頁。
  void _back(BuildContext context, bool editMode) {
    if (editMode) {
      context.pop();
    } else {
      context.go('/setup/group-name');
    }
  }

  /// 進入上傳畫面設定某組員頭像。刻意用「根 Navigator 推出」而非 go_router：
  /// 上傳頁是回傳值的子畫面，放在 Navigator 上，go_router 的 refreshListenable
  /// （setMemberAvatarUrl 會觸發）重整時不會把它還原，避免回到總覽後又被推回上傳頁。
  Future<void> _editMember(BuildContext context, String seat) async {
    final appState = context.read<AppState>();
    final url = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => UploadAvatarScreen(
          target: AvatarTarget.member,
          memberSeat: seat,
        ),
      ),
    );
    if (url != null) appState.setMemberAvatarUrl(seat, url);
  }

  /// 橫向組員卡片帶：人數少時置中（minWidth = 視窗寬），人數多時可左右滑動。
  Widget _memberStrip(BuildContext context, List<UserModel> members) {
    return LayoutBuilder(
      builder: (_, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                _MemberCard(
                  member: members[i],
                  onEdit: () => _editMember(context, members[i].seatNumber),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomButton(BuildContext context, bool editMode) {
    return SizedBox(
      width: 200,
      child: ElevatedButton(
        onPressed: () {
          if (editMode) {
            context.pop();
          } else {
            context.read<AppState>().completeSetup();
            context.go('/heritage-selection');
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: Text(
          editMode ? '完 成' : '進 入 遊 戲',
          style: const TextStyle(
            fontSize: 18,
            letterSpacing: 4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── 左上小組標頭 ─────────────────────────────────────────────────────────────
class _GroupHeader extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  const _GroupHeader({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 28, 12),
      decoration: const BoxDecoration(
        color: Color(0xF03A332E),
        // 膠囊形狀
        borderRadius: BorderRadius.all(Radius.circular(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvatarCircle(url: avatarUrl, size: 72),
          const SizedBox(width: 16),
          Text(
            name.isEmpty ? '未命名小組' : name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 組員卡片 ─────────────────────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final UserModel member;
  final VoidCallback onEdit;

  const _MemberCard({required this.member, required this.onEdit});

  static const double _w = 156;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onEdit,
            child: Stack(
              children: [
                _AvatarCircle(url: member.personalAvatarUrl, size: _w),
                // 右下角編輯 icon（點卡片可改該組員頭像）
                const Positioned(right: 6, bottom: 6, child: _EditBadge()),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: _w,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE3CC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x33000000)),
            ),
            child: Text(
              '${member.seatNumber}  ${member.name}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF4A3B2A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 卡片右下角的編輯標記。
class _EditBadge extends StatelessWidget {
  const _EditBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xF03A332E),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: const Icon(Icons.edit, color: Colors.white, size: 17),
    );
  }
}

// 共用的圓形頭像（小組標頭與組員卡片共用），含預設人像。
class _AvatarCircle extends StatelessWidget {
  final String? url;
  final double size;

  const _AvatarCircle({this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Color(0xFFDDD0BA),
        shape: BoxShape.circle,
      ),
      child: _image(),
    );
  }

  Widget _image() {
    final u = url;
    if (u == null) {
      return Icon(
        Icons.person,
        size: size * 0.5,
        color: const Color(0xFFAA9A88),
      );
    }
    final remote = u.startsWith('http://') || u.startsWith('https://');
    return remote
        ? Image.network(u, fit: BoxFit.cover, width: size, height: size)
        : Image.file(File(u), fit: BoxFit.cover, width: size, height: size);
  }
}
