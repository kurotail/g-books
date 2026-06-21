import 'models/group_account.dart';
import 'models/roster_student.dart';
import 'models/staff_account.dart';

// 新模型（一組一帳號 + 班級名冊）的 mock 種子，供 kUseBackend=false 離線開發。

// 班級名冊：每筆 = 一位學生 {座號, 姓名, 頭像}（非登入帳號）。
// id 為唯一鍵（mock 沿用舊座號值當鍵）；seatNo 為顯示用座號。
final mockRoster = <RosterStudent>[
  RosterStudent(id: 1, seatNo: 1, name: '王小明'),
  RosterStudent(id: 2, seatNo: 2, name: '李小花'),
  RosterStudent(id: 3, seatNo: 3, name: '張大山'),
  RosterStudent(id: 4, seatNo: 4, name: '陳小芳'),
  RosterStudent(id: 5, seatNo: 5, name: '林小豪'),
  RosterStudent(id: 6, seatNo: 6, name: '黃小玲'),
  RosterStudent(id: 7, seatNo: 7, name: '史塔克'),
  RosterStudent(id: 11, seatNo: 11, name: '周杰'),
  RosterStudent(id: 15, seatNo: 15, name: '趙鐵柱'),
  RosterStudent(id: 18, seatNo: 18, name: '張俊生'),
  RosterStudent(id: 20, seatNo: 20, name: '皮克敏'),
  RosterStudent(id: 25, seatNo: 25, name: '吳小萌'),
  RosterStudent(id: 32, seatNo: 32, name: '陳眼鏡'),
];

// 小組帳號：username 即組名（亦為登入帳號），持有指派的名冊成員。每組人數刻意不同，
// 用來驗證小組總攬的「多人左右滑動 / 少人置中」版面。id 模擬後端 user_id。
final mockGroupAccounts = <GroupAccount>[
  GroupAccount(id: 1, username: '第一組', studentIds: [1, 2, 7, 15, 18, 20, 32]),
  GroupAccount(id: 2, username: '第二組', studentIds: [3, 4]),
  GroupAccount(id: 3, username: '第三組', studentIds: [5, 6, 11, 25]),
];

// mock 模式下各組帳號的密碼（後端模式由後端驗證；此處供單機 demo 登入）。
final mockGroupPasswords = <String, String>{
  '第一組': '1234',
  '第二組': '1234',
  '第三組': '1234',
};

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
