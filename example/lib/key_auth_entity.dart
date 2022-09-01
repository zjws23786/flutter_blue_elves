class KeyAuthEntity{
  late String endTime;
  late String groupNo;
  late bool isPsw;
  late bool isTime;
  late String lockId;
  late String startTime;
  String? psw;

  KeyAuthEntity(this.groupNo,this.startTime,this.endTime,this.lockId,this.isPsw,this.isTime,{this.psw});
}