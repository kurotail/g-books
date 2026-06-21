import 'models/group_account.dart';
import 'models/roster_student.dart';
import 'models/staff_account.dart';

// 新模型（一組一帳號 + 班級名冊）的 mock 種子，供 kUseBackend=false 離線開發。

// 班級名冊：每筆 = 一位學生 {座號, 姓名, 頭像}（非登入帳號）。
final mockRoster = <RosterStudent>[
  RosterStudent(id: 1, name: '王小明'),
  RosterStudent(id: 2, name: '李小花'),
  RosterStudent(id: 3, name: '張大山'),
  RosterStudent(id: 4, name: '陳小芳'),
  RosterStudent(id: 5, name: '林小豪'),
  RosterStudent(id: 6, name: '黃小玲'),
  RosterStudent(id: 7, name: '史塔克'),
  RosterStudent(id: 11, name: '周杰'),
  RosterStudent(id: 15, name: '趙鐵柱'),
  RosterStudent(id: 18, name: '張俊生'),
  RosterStudent(id: 20, name: '皮克敏'),
  RosterStudent(id: 25, name: '吳小萌'),
  RosterStudent(id: 32, name: '陳眼鏡'),
];

// 小組帳號：username 即組名（亦為登入帳號），持有指派的名冊成員。每組人數刻意不同，
// 用來驗證小組總攬的「多人左右滑動 / 少人置中」版面。
final mockGroupAccounts = <GroupAccount>[
  GroupAccount(username: '第一組', studentIds: [1, 2, 7, 15, 18, 20, 32]),
  GroupAccount(username: '第二組', studentIds: [3, 4]),
  GroupAccount(username: '第三組', studentIds: [5, 6, 11, 25]),
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
