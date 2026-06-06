import 'models/user_model.dart';
import 'models/group_model.dart';

final mockUsers = [
  UserModel(name: '王小明', seatNumber: '1', groupId: 1, isLeader: true),
  UserModel(name: '李小花', seatNumber: '2', groupId: 1, isLeader: false),
  UserModel(name: '張大山', seatNumber: '3', groupId: 2, isLeader: true),
  UserModel(name: '陳小芳', seatNumber: '4', groupId: 2, isLeader: false),
  UserModel(name: '林小豪', seatNumber: '5', groupId: 3, isLeader: true),
  UserModel(name: '黃小玲', seatNumber: '6', groupId: 3, isLeader: false),
];

final mockGroups = [
  GroupModel(id: 1),
  GroupModel(id: 2),
  GroupModel(id: 3),
];
