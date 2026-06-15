import 'models/user_model.dart';
import 'models/group_model.dart';
import 'models/staff_account.dart';

// 以小組為主的登入：學生由「組長」帳號登入整組。每組人數刻意不同，
// 用來驗證小組總攬的「多人左右滑動 / 少人置中」版面。
final mockUsers = [
  // 第 1 組：人數較多，7 人（測試左右滑動）
  UserModel(name: '王小明', seatNumber: '1', groupId: 1, isLeader: true),
  UserModel(name: '李小花', seatNumber: '2', groupId: 1, isLeader: false),
  UserModel(name: '張俊生', seatNumber: '18', groupId: 1, isLeader: false),
  UserModel(name: '史塔克', seatNumber: '7', groupId: 1, isLeader: false),
  UserModel(name: '陳眼鏡', seatNumber: '32', groupId: 1, isLeader: false),
  UserModel(name: '皮克敏', seatNumber: '20', groupId: 1, isLeader: false),
  UserModel(name: '趙鐵柱', seatNumber: '15', groupId: 1, isLeader: false),
  // 第 2 組：人數較少（測試置中）
  UserModel(name: '張大山', seatNumber: '3', groupId: 2, isLeader: true),
  UserModel(name: '陳小芳', seatNumber: '4', groupId: 2, isLeader: false),
  // 第 3 組：約參考圖人數（4 人）
  UserModel(name: '林小豪', seatNumber: '5', groupId: 3, isLeader: true),
  UserModel(name: '黃小玲', seatNumber: '6', groupId: 3, isLeader: false),
  UserModel(name: '周杰', seatNumber: '11', groupId: 3, isLeader: false),
  UserModel(name: '吳小萌', seatNumber: '25', groupId: 3, isLeader: false),
];

final mockGroups = [
  GroupModel(id: 1),
  GroupModel(id: 2),
  GroupModel(id: 3),
];

// 後台（教師 / 管理者）帳號。現階段為假後端 mock；之後改由後端登入驗證。
const mockStaff = <StaffAccount>[
  StaffAccount(
    username: 'admin',
    password: 'admin123',
    displayName: '系統管理者',
    role: StaffRole.admin,
  ),
  StaffAccount(
    username: 'teacher',
    password: 'teacher123',
    displayName: '王老師',
    role: StaffRole.teacher,
  ),
];
