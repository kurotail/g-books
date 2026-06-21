import 'dart:io';
import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/parchment_scaffold.dart';
import '../../core/widgets/step_indicator.dart';
import '../../core/widgets/avatar_frame.dart';
import '../../state/app_state.dart';

/// 此畫面要設定哪一種頭像。
/// - [group] ：小組頭像，屬於初次登入的線性設定流程（→ 小組命名）。
/// - [member]：某位組員（含組長本人）的個人頭像，由小組總攬點卡片進入，完成後返回。
enum AvatarTarget { group, member }

enum _Stage { picking, cropping, previewing, uploading }

class UploadAvatarScreen extends StatefulWidget {
  final AvatarTarget target;

  /// 當 [target] 為 [AvatarTarget.member] 時，要編輯的組員學號（student_id）。
  final int? memberId;

  const UploadAvatarScreen({super.key, required this.target, this.memberId});

  bool get isGroup => target == AvatarTarget.group;

  @override
  State<UploadAvatarScreen> createState() => _UploadAvatarScreenState();
}

class _UploadAvatarScreenState extends State<UploadAvatarScreen> {
  final _cropController = CropController();
  final _picker = ImagePicker();

  _Stage _stage = _Stage.picking;
  Uint8List? _pickedBytes; // raw image bytes — kept for re-crop
  String? _croppedPath; // temp file path after circle crop
  String? _uploadError;
  bool _isCropping = false; // waiting for cropCircle() callback

  // ── image picking ────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (!mounted || picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedBytes = bytes;
      _croppedPath = null;
      _stage = _Stage.cropping;
      _uploadError = null;
    });
  }

  // ── cropping (pure Flutter, no Activity) ─────────────────────────────────

  void _triggerCrop() {
    setState(() => _isCropping = true);
    _cropController.cropCircle();
  }

  void _onCropResult(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        _saveCrop(croppedImage);
      case CropFailure():
        if (mounted) setState(() => _isCropping = false);
    }
  }

  Future<void> _saveCrop(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(bytes);
    if (!mounted) return;
    setState(() {
      _croppedPath = path;
      _stage = _Stage.previewing;
      _isCropping = false;
    });
  }

  // ── confirm / skip / back ────────────────────────────────────────────────

  Future<void> _onConfirm() async {
    final state = context.read<AppState>();
    setState(() {
      _stage = _Stage.uploading;
      _uploadError = null;
    });

    String? url;
    if (_croppedPath != null) {
      url = await state.avatarService.upload(_croppedPath!);
      if (!mounted) return;
      if (url == null) {
        setState(() {
          _stage = _Stage.previewing;
          _uploadError = '上傳失敗，請重試';
        });
        return;
      }
    }

    if (widget.isGroup) {
      state.setGroupAvatarUrl(url);
      context.go('/setup/group-name');
    } else {
      // 組員頭像由總覽用根 Navigator 推出，這裡用 Navigator.pop 回傳 url，
      // 不經 go_router、不在此改狀態，避免 refresh 把上傳頁又還原。
      Navigator.of(context).pop(url);
    }
  }

  // 略過僅用於小組頭像（組員頭像不可略過，要離開改用返回鍵）。
  void _onSkip() => context.go('/setup/group-name');

  void _onBack() {
    switch (_stage) {
      case _Stage.cropping:
        setState(() {
          _stage = _Stage.picking;
          _pickedBytes = null;
        });
      case _Stage.previewing:
        // re-enter crop with same _pickedBytes
        setState(() => _stage = _Stage.cropping);
      case _Stage.picking:
        if (widget.isGroup) {
          // 小組頭像是設定流程第一步，返回即回登入頁。
          context.read<AppState>().logout();
        } else {
          // 組員頭像走 Navigator，返回不帶結果（不更新頭像）。
          Navigator.of(context).pop();
        }
      case _Stage.uploading:
        break;
    }
  }

  /// 進入畫面時預覽框要顯示的既有頭像（裁切後改顯示裁切結果）。
  String? _initialAvatar(AppState state) {
    if (widget.isGroup) return state.currentGroup?.avatarUrl;
    final id = widget.memberId;
    return id == null ? null : state.memberById(id)?.avatarUrl;
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: switch (_stage) {
        _Stage.cropping => _buildCropStage(),
        _ => _buildNormalStage(),
      },
    );
  }

  /// Full-screen dark crop UI — no ParchmentScaffold, no step indicator.
  Widget _buildCropStage() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isCropping ? null : _onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Spacer(),
                  const Text(
                    '調整頭像位置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // crop widget
            Expanded(
              child: _pickedBytes != null
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Crop(
                          image: _pickedBytes!,
                          controller: _cropController,
                          onCropped: _onCropResult,
                          withCircleUi: true,
                          aspectRatio: 1.0,
                          initialRectBuilder:
                              InitialRectBuilder.withSizeAndRatio(size: 1.0),
                          interactive: true,
                          fixCropRect: true,
                          baseColor: Colors.black,
                          maskColor: Colors.black54,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // bottom buttons — fixed height prevents Crop widget constraints
            // from changing, which would trigger _resetCropRect() and reset
            // the image position the user just set.
            SizedBox(
              height: 88,
              child: Center(
                child: _isCropping
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _cropBtn('取 消', _onBack, light: false),
                          _cropBtn('確定裁切', _triggerCrop, light: true),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Normal parchment layout for picking / previewing / uploading.
  Widget _buildNormalStage() {
    final state = context.watch<AppState>();
    final isUploading = _stage == _Stage.uploading;
    final title = _title(state);
    final preview = _croppedPath ?? _initialAvatar(state);

    return ParchmentScaffold(
      child: Stack(
        children: [
          // back（往畫面內側收一點，避免太靠近螢幕邊緣）
          Positioned(
            top: 32,
            right: 56,
            child: GestureDetector(
              onTap: isUploading ? null : _onBack,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.pillDark
                      .withValues(alpha: isUploading ? 0.5 : 0.94),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: isUploading ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // step indicator — 小組頭像屬設定流程才顯示；改組員頭像為子流程不顯示。
          if (widget.isGroup)
            const Positioned(
              right: 40,
              top: 0,
              bottom: 0,
              width: 160,
              child: Center(
                child: StepIndicator(
                  steps: _setupSteps,
                  currentStep: 1,
                ),
              ),
            ),
          // main content：標題稍微下移、頭像與按鈕整組往畫面中央靠。
          Positioned.fill(
            child: Column(
              children: [
                const Spacer(flex: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.labelText,
                  ),
                ),
                const SizedBox(height: 32),
                AvatarFrame(size: 260, imageUrl: preview),
                const SizedBox(height: 16),
                if (_uploadError != null)
                  Text(
                    _uploadError!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                const SizedBox(height: 32),
                if (isUploading)
                  const CircularProgressIndicator(color: AppColors.buttonDark)
                else if (_stage == _Stage.picking)
                  _buildPickButtons()
                else
                  _buildPreviewButtons(),
                const Spacer(flex: 4),
              ],
            ),
          ),
          // skip — 僅小組頭像可略過
          if (!isUploading && widget.isGroup)
            Positioned(
              bottom: 20,
              right: 48,
              child: GestureDetector(
                onTap: _onSkip,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '略 過',
                      style: TextStyle(
                        color: AppColors.labelText,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.labelText,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 設定流程的步驟列（已移除獨立的「個人頭像」步驟，組員頭像改於小組總攬設定）。
  static const _setupSteps = ['登陸帳號', '小組頭像', '小組命名', '小組建立成功'];

  String _title(AppState state) {
    if (widget.isGroup) return '利用上傳或拍照功能建立小組頭像吧！';
    final id = widget.memberId;
    final name = (id == null ? null : state.memberById(id)?.name) ?? '組員';
    return '為 $name 上傳頭像吧！';
  }

  Widget _buildPickButtons() => Column(
    children: [
      _btn('上 傳 照 片', () => _pickImage(ImageSource.gallery)),
      const SizedBox(height: 16),
      _btn('拍 攝 照 片', () => _pickImage(ImageSource.camera)),
    ],
  );

  Widget _buildPreviewButtons() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _btn(
        '確 定',
        () {
          _onConfirm();
        },
        dark: false,
        width: 140,
      ),
      const SizedBox(width: 12),
      _btn('重新裁切', () => setState(() => _stage = _Stage.cropping), width: 140),
      const SizedBox(width: 12),
      _btn(
        '重新選取',
        () => setState(() {
          _stage = _Stage.picking;
          _pickedBytes = null;
          _croppedPath = null;
        }),
        width: 140,
      ),
    ],
  );

  Widget _btn(
    String label,
    VoidCallback onTap, {
    bool dark = true,
    double width = 240,
  }) => SizedBox(
    width: width,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        // 「確定」用品牌金色，與淺色背景 / 旁邊的深色鈕都明顯區隔。
        backgroundColor: dark ? AppColors.buttonDark : AppColors.accentGold,
        foregroundColor: dark ? Colors.white : AppColors.labelText,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 17,
          letterSpacing: 3,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _cropBtn(String label, VoidCallback onTap, {required bool light}) =>
      ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: light ? Colors.white : Colors.white24,
          foregroundColor: light ? Colors.black87 : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
}
