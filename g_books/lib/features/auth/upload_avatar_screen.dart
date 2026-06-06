import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../core/widgets/step_indicator.dart';
import '../../core/widgets/avatar_frame.dart';
import '../../state/app_state.dart';

class UploadAvatarScreen extends StatefulWidget {
  /// true = 上傳小組頭貼（組長專用），false = 上傳個人頭貼
  final bool isGroup;

  const UploadAvatarScreen({super.key, required this.isGroup});

  @override
  State<UploadAvatarScreen> createState() => _UploadAvatarScreenState();
}

class _UploadAvatarScreenState extends State<UploadAvatarScreen> {
  String? _imagePath;
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file != null) setState(() => _imagePath = file.path);
  }

  void _onConfirm() {
    final state = context.read<AppState>();
    if (widget.isGroup) {
      state.setGroupAvatar(_imagePath);
      context.go('/setup/group-name');
    } else {
      state.setPersonalAvatar(_imagePath);
      _goNext(state);
    }
  }

  void _onSkip() {
    final state = context.read<AppState>();
    if (widget.isGroup) {
      context.go('/setup/group-name');
    } else {
      _goNext(state);
    }
  }

  void _onBack() {
    if (widget.isGroup) {
      context.go('/setup/personal-avatar');
    } else {
      context.read<AppState>().logout();
      // GoRouter redirect sends back to /login
    }
  }

  void _goNext(AppState state) {
    if (state.currentUser!.isLeader) {
      context.go('/setup/group-avatar');
    } else {
      state.completeSetup();
      context.go('/heritage-selection');
    }
  }

  List<String> _steps(AppState state) {
    if (state.currentUser?.isLeader ?? false) {
      return ['登陸帳號', '上傳個人頭貼', '上傳小組頭貼', '小組命名', '完成'];
    }
    return ['登陸帳號', '上傳個人頭貼', '完成'];
  }

  int get _currentStep => widget.isGroup ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final title = widget.isGroup
        ? '利用上傳或拍照功能建立小組頭像吧！'
        : '利用上傳或拍照功能建立個人頭像吧！';

    return ParchmentScaffold(
      child: Stack(
        children: [
          // Back arrow
          Positioned(
            top: 36,
            right: 48,
            child: GestureDetector(
              onTap: _onBack,
              child: const Text(
                '↩',
                style: TextStyle(fontSize: 30, color: Color(0xFF6A6A6A)),
              ),
            ),
          ),
          // Step indicator
          Positioned(
            right: 40,
            top: 0,
            bottom: 0,
            width: 160,
            child: Center(
              child: StepIndicator(
                steps: _steps(state),
                currentStep: _currentStep,
              ),
            ),
          ),
          // Main content
          Positioned(
            left: 0,
            right: 220,
            top: 0,
            bottom: 0,
            child: Column(
              children: [
                const SizedBox(height: 60),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.labelText,
                  ),
                ),
                const Spacer(),
                AvatarFrame(size: 260, imagePath: _imagePath),
                const Spacer(),
                if (_imagePath == null) _buildUploadButtons() else _buildConfirmButtons(),
                const SizedBox(height: 48),
              ],
            ),
          ),
          // Skip
          Positioned(
            bottom: 20,
            right: 48,
            child: GestureDetector(
              onTap: _onSkip,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('略 過', style: TextStyle(color: AppColors.labelText, fontSize: 16)),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: AppColors.labelText, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButtons() => Column(
        children: [
          _btn('上 傳 照 片', () => _pickImage(ImageSource.gallery)),
          const SizedBox(height: 16),
          _btn('拍 攝 照 片', () => _pickImage(ImageSource.camera)),
        ],
      );

  Widget _buildConfirmButtons() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _btn('確 定', _onConfirm, dark: false, width: 160),
          const SizedBox(width: 16),
          _btn('重新上傳', () => _pickImage(ImageSource.gallery), width: 160),
        ],
      );

  Widget _btn(
    String label,
    VoidCallback onTap, {
    bool dark = true,
    double width = 240,
  }) =>
      SizedBox(
        width: width,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: dark ? AppColors.buttonDark : AppColors.buttonLight,
            foregroundColor: dark ? Colors.white : AppColors.labelText,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 0,
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 17, letterSpacing: 3, fontWeight: FontWeight.w600),
          ),
        ),
      );
}
