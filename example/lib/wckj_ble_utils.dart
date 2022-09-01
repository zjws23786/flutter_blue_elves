import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_elves_example/personal_entity.dart';

import 'hex.dart';
import 'key_auth_entity.dart';

class WCKJBleUtils {
  static List<int> MyCode = dataToByte(
      "E62B2525BD24756BE22A6974A172255FAD7D5E27AF715E27A2064020A418255FD92D682AB56E2B33A9742E62E23C6F68ED31644BC5124254CE116A77F4326B72");
  static final String WCKJ_SERVICE_UUID = Platform.isAndroid ? "0000ffe0-0000-1000-8000-00805f9b34fb":"FFE0";
  static final String WCKJ_CHARACT_UUID = Platform.isAndroid ? "0000ffe1-0000-1000-8000-00805f9b34fb":"FFE1";

  static String head = "EA"; //EA
  static String tail = "59"; //59
  static String keyId = "87580002";

  static String readKeyIdCommand() {
    String data = "0C00";
    data = data + checksum(data);
    String length = getLength(data);
    String command = "FFFFFFFF" + length + data;
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  static String checksum(String data) {
    List<int> bytes = dataToByte(data);
    int N = bytes.length;
    int D_Checksum = 0; //计算和
    for (int i = 0; i < N; i++) {
      D_Checksum += (bytes[i] & 0xff) ^ i;
    }
    print("D_Checksum=" + D_Checksum.toString());

    List<int> c = [];
    c.add(((D_Checksum >> 8) & 0xff));
    c.add((D_Checksum & 0xff));
    return toHexStr(c);
  }

  static bool isDataComplete(String buf) {
    if (buf.length <= 12) return false;
    if (int.parse(buf.substring(0, 2), radix: 16) == 234 &&
        int.parse(buf.substring(buf.length - 2, buf.length), radix: 16) == 89) {
      if ((int.parse(buf.substring(10, 12), radix: 16) * 2 + 16) ==
          buf.length) {
        return true;
      }
    }
    return false;
  }

  static bool isDataCompleteEB(String buf) {
    if (buf.length <= 12) return false;
    if (int.parse(buf.substring(0, 2), radix: 16) == 235 &&
        int.parse(buf.substring(buf.length - 2, buf.length), radix: 16) ==
            145) {
      if ((int.parse(buf.substring(10, 12), radix: 16) * 2 + 16) ==
          buf.length) {
        return true;
      }
    }
    return false;
  }

  ///发送握手请求
  static String sendHandShake(String buf) {
    String handCode = readHandShakeMessage(buf); //随机数
    String checkCode = getHandCheckCode(handCode);
    String data = "1500" + handCode + checkCode;
    data = data + checksum(data);
    String length = getLength(data);
    // print("hjz length = "+length);
    String command = "FFFFFFFF" + length + data;
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  static String encodeWithData(String buf){
    String blueId = buf.substring(4, 12); // 芯片ID
    String num = buf.substring(12, 28); // 随机数
    List<int> Random = dataToByte(blueId + num);
    int N = Random.length;
    List<int> command = [];
    for (int i = 0; i < N; i++) {
      command.add((((Random[i] & 0xff) * ((Random[i] & 0x0F) + 2)) & 0xff));
    }
    int sum = 0;
    for (int i = 0; i < command.length; i++) {
      sum = sum + (command[i] & 0xff);
    }
    sum += 0xab;
    sum = 0x100 - (sum & 0xff); // 取低八位0xff
    String checkCode = sum.toRadixString(16).length >  1 ?
    sum.toRadixString(16).substring(0,2): "0" + sum.toRadixString(16);
    print("command=${toHexStr(command)}");
    String cmdStr = ("AA01" + toHexStr(command) + checkCode).toLowerCase();
    print("cmdStr="+cmdStr);
    return cmdStr;
  }

//  发送蓝牙开门握手协议
  static String sendBluethLockHandShake(String buf) {
    String blueId = buf.substring(4, 12); // 芯片ID
    String num = buf.substring(12, 28); // 随机数
    List<int> Random = dataToByte(blueId + num);
    int N = Random.length;
    List<int> command = [];
    for (int i = 0; i < N; i++) {
      command.add(((Random[i] * ((Random[i] & 0x0F) + 2)) & 0xFF));
    }
    List<int> code = dataToByte("AA01" + toHexStr(command));
    int sum = 0;
    for (int i = 0; i < code.length; i++) {
      sum = sum + code[i];
    }
    sum = 0x100 - (sum & 0xff); // 取低八位0xff
    String checkCode = sum.toRadixString(16).length >  1 ?
    sum.toRadixString(16).substring(0,2): "0" + sum.toRadixString(16);
    String cmdStr = "AA01" + toHexStr(command) + checkCode;
    print("cmdStr="+cmdStr);
    return cmdStr;
  }

  ///解析读取设备id
  static String readKeyIdMessage(String buf) {
    List<int> newBuf = dataToByte(buf.substring(12, buf.length - 4));
    int stateCode = newBuf[1] > 0 ? newBuf[1] : (256 + newBuf[1]); // 状态码
    print("stateCode=$stateCode");
    String temp = toHexStr(newBuf); // 前4位表示命令码和状态码
    print("keyId temp="+temp);
    if (stateCode == 170) {
      // 170 0xAA表示成功
      keyId = temp.substring(4, 12);
      print("keyId="+keyId);
      String psw = temp.substring(12);
      return "读取成功!";
    } else if (stateCode == 85) {
      return "读取失败!";
    } else {
      return "未知原因!";
    }
  }

  ///读取开门记录命令
  static String readRecordCommand() {
    String data = toHexStr(enAndDec(dataToByte("0600" + checksum("0600"))));
    print("读取开门记录命令data = $data");
    String length = getLength(data);
    print("读取开门记录命令length = $length");
    String command = keyId + length + data;
    print("读取开门记录命令command = $command");
    List<int> code = [getCode(dataToByte(command))];
    print("读取开门记录命令code = $code");
    return head + command + toHexStr(code) + tail;
  }

  ///读取门锁记录结果判断
  static String readLockRecordMessage(String buf) {
    String head = buf.substring(0, 12);
    String tail = buf.substring((buf.length - 4), buf.length);
    List<int> newBuf =
        dataToByte(buf.substring(12, buf.length - 4)); // .getBytes();
    newBuf = enAndDec(newBuf);
    String temp = toHexStr(newBuf);
    if (temp.substring(0, 4) == "06AA") {
      String record = head + temp + tail;
      try {
        // FileUtils.saveFile(record, "smartLock", "wckjBleRecord.txt");
      } catch (e) {}
      return "读取开锁记录成功!";
    }
    if (temp.substring(0, 4) == "06A5") {
      return "暂无最新记录!";
    }
    return "读取开锁记录失败!";
  }

  ///设置时间命令
  static String setDeviceTime(String time){
    print("time="+time);
    String s = time2HexStr(time, 1);
    String data = toHexStr(enAndDec(dataToByte("0200" + s + checksum("0200" + s)))); // 0100->428D
    String length = getLength(data);
    String command = keyId + length + data;
    print("command="+command);
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  ///读取锁芯编码
  static String sendReadLockCommand() {
    String data = toHexStr(enAndDec(dataToByte("0100"+checksum("0100"))));
    String length = getLength(data);
    String command = keyId + length + data;;
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  //读取电量信息
  static String readElectricMessage(String buf) {
    List<int> newBuf = dataToByte(buf.substring(0xc, (buf.length - 0x4)));
    newBuf = enAndDec(newBuf);
    int stateCode = newBuf[0x1] >= 0 ? newBuf[0x1] : newBuf[0x1] + 0x100;
    String temp = toHexStr(newBuf); // 前4位表示命令码和状态码
    if (stateCode == 0xaa) {
      return "读取成功" + temp;
    }
    if (stateCode == 0xff) {
      return "读取失败!";
    }
    return "未知原因!";
  }

  ///删除所有权限和人员
  static String deleteAllAuth() {
    String data = toHexStr(enAndDec(dataToByte("0B0030"+checksum("0B0030"))));
    String length = getLength(data);
    String command = keyId + length + data;
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  //设置一组人员信息命令
  static String setGroupPersonCommand(List<PersonalEntity> list) {
    // 组建人员信息 00+3字节ID+4字节登录密码，16个人员信息
    String groupNo = list[0].groupNo;
    String group = "";
    String id;
    String psw;
    for (int i = 0; i < list.length; i++) {
      id = list[i].id;
      psw = (int.parse(list[i].psw) - 11111111).toString();
      String temp;
      int size = 8 - psw.length;
      if (psw.length < 8) {
        for (int j = 0; j < size; j++) {
          psw = "0" + psw;
        }
      }
      temp = "00" + id + psw;
      group += temp;
    }
    int count = list.length;
    while (count < 16) {
      group += "FFFFFFFFFFFFFFFF";
      ++count;
    }
    // print("group====="+group);
    // print("group====="+toHexStr(enAndDec(dataToByte(group))));
    // print("data="+"0900" + groupNo + group+checksum("0900" + groupNo + group));
    // String aa = checksum("0900" + groupNo + group);
    // String bb = toHexStr(enAndDec(dataToByte("0900" + groupNo + group+checksum("0900" + groupNo + group))));
    // String cc = toHexStr(enAndDec(dataToByte("0900" + groupNo + group)));
    // String q = toHexStr(enAndDec(dataToByte("0900")));
    // String w = toHexStr(enAndDec(dataToByte(groupNo)));
    // String e = toHexStr(enAndDec(dataToByte(group)));
    // String dd = toHexStr(enAndDec(dataToByte(checksum("0900" + groupNo + group))));
    String data = toHexStr(enAndDec(dataToByte("0900" + groupNo + group+checksum("0900" + groupNo + group))));
    // print("data=$data");
    String length = getLength(data);
    String command = keyId + length + data;
    // print("command=$command");
    List<int> code = [getCode(dataToByte(command))];
    String codeStr = toHexStr(code);
    // print("code=$codeStr");
    String cmdStr = head + command + codeStr + tail;
    // print("cmd====="+head + command + codeStr + tail);
    // print("cmdStr=====$cmdStr");
    return cmdStr.toString();
  }

 //设置一组权限
  static String setGroupAuthCommand(List<KeyAuthEntity> list) {
    String groupNo = list[0].groupNo;
    String group = "";
    for (int i = 0; i < list.length; i = i + 1) {
      String id = list[i].lockId;
      bool isPsw = list[i].isPsw;
      bool isTime = list[i].isTime;
      String? psw = list[i].psw;
      String temp = "";
      if (isPsw && psw != null) {
        temp = id + (int.parse(psw) - 0xa98ac7).toString();
      } else {
        temp = id + "FFFFFFFF";
      }
      if (isTime) {
        if (list[i].startTime.isNotEmpty && list[i].endTime.isNotEmpty) {
          temp = temp + time2HexStr(list[i].startTime, 0x2) + time2HexStr(list[i].endTime, 0x2);
        } else {
          temp = temp + "FF000000" + "FF000000";
        }
      } else {
        if (list[i].startTime.isNotEmpty && list[i].endTime.isNotEmpty) {
          temp = temp + "FF" + time2HexStr(list[i].startTime, 0x2).substring(0x2) + time2HexStr(list[i].endTime, 0x2);
        } else {
          temp = temp + "FF000000" + "FF000000";
        }

      }
      group = group + temp;
    }
    int count = list.length;
    while (count < 0x8) {
      group = group + "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
      count = count + 0x1;
    }


    String data = toHexStr(enAndDec(dataToByte("0A00" + groupNo + group+checksum("0A00" + groupNo + group))));
    String length = getLength(data);
    String command = keyId + length + data;
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  ///设置休眠时间
  static String setSleepTime(int time) {
    String timeStr = time.toRadixString(16);
    int len = timeStr.length;
    if (len < 4) {
      for (int i = len; i < 4; i++) {
        timeStr = "0" + timeStr;
      }
    }
    String data = toHexStr(
        enAndDec(dataToByte("0D00" + 20.toRadixString(16) + timeStr+checksum("0D00" + 20.toRadixString(16) + timeStr))));
    String length = getLength(data);
    String command;
    if (length.length == 1) {
      command = keyId + "0" + length + data;
    } else {
      command = keyId + length + data;
    }
    List<int> code = [getCode(dataToByte(command))];
    return head + command + toHexStr(code) + tail;
  }

  static String readGroupPersonMessage(String buf) {
    List<int> newBuf = dataToByte(buf.substring(0xc, (buf.length - 0x4)));
    newBuf = enAndDec(newBuf);
    int stateCode = newBuf[0x1] >= 0 ? newBuf[0x1] : newBuf[0x1] + 0x100;
    if (stateCode == 0xaa) {
      return "成功";
    }
    if (stateCode == 0x55) {
      return "失败!";
    }
    return "未知原因!";
  }

  static String readReturnMessage(String buf) {
    List<int> newBuf = dataToByte(buf.substring(0xc, (buf.length - 0x4)));
    newBuf = enAndDec(newBuf);
    int stateCode = newBuf[0x1] >= 0 ? newBuf[0x1] : newBuf[0x1] + 0x100;
    if (stateCode == 0xaa) {
      return "读取成功!";
    }
    if (stateCode == 0x55) {
      return "读取失败!";
    }
    return "未知原因!";
  }

  static String time2HexStr(String str, int type) {
    String year = int.parse(str.substring(0x2, 0x4)).toRadixString(16);
    String month = int.parse(str.substring(0x5, 0x7)).toRadixString(16);
    String day = int.parse(str.substring(0x8, 0xa)).toRadixString(16);
    String hour = int.parse(str.substring(0xb, 0xd)).toRadixString(16);
    String min = int.parse(str.substring(0xe, 0x10)).toRadixString(16);
    String sec = int.parse(str.substring(0x11, 0x13)).toRadixString(16);
    if (year.length == 0x1) {
      year = "0" + year;
    }
    if (month.length == 0x1) {
      month = "0" + month;
    }
    if (day.length == 0x1) {
      day = "0" + day;
    }
    if (hour.length == 0x1) {
      hour = "0" + hour;
    }
    if (min.length == 0x1) {
      min = "0" + min;
    }
    if (sec.length == 0x1) {
      sec = "0" + sec;
    }
    if (type == 0x1) {
      return year + month + day + hour + min + sec;
    }
    return year + month + day + hour;
  }

  ///读取握手信息
  static String readHandShakeMessage(String buf) {
    String handCode = buf.substring(16, 32);
    return handCode;
  }

  static String getHandCheckCode(String handCode) {
    List<int> Random = dataToByte(handCode);
    int N = Random.length;
    List<int> Check = <int>[];
    for (int i = 0; i < N; i++) {
      Check.add((Random[i] * (i + 1) & 0xFF) ^ 0xa5);
    }
    String checkCode = toHexStr(Check);
    return checkCode;
  }

  //bytes转换成十六进制字符串toHexStr
  static String toHexStr(List<int> dataByte) {
    //字符串转换成字节数组
    List<int> hex = utf8.encode("0123456789ABCDEF");
    List<int> buff = <int>[];
    for (int i = 0x0; i < dataByte.length; i = i + 0x1) {
      buff.add(hex[((dataByte[i] >> 0x4) & 0xf)]);
      buff.add(hex[(dataByte[i] & 0xf)]);
    }
    //字节数组转换成字符串
    return utf8.decode(buff);
  }

  //16进制字符串转byte
  static List<int> dataToByte(String data) {
    List<int> daBy = [];
    if (data != null && data.length > 0) {
      int length = data.length;
      int forLength = (length ~/ 2) + 1;
      for (int i = 1; i < forLength; i++) {
        int bgIndex = (i * 2) - 2;
        String str = data.substring(bgIndex, bgIndex + 2);
        int num = int.parse(str, radix: 16) & 0xff;
        daBy.add(num);
      }
    }
    return daBy;
  }

  static List<int> enAndDec(List<int> buf) {
    int N = buf.length;
    for (int i = 0x0; i < N; i = i + 0x1) {
      buf[i] = ((buf[i] ^ MyCode[(i % 0x40)]) ^ (i + 0xa5));
    }
    return buf;
  }

  //长度是否需要补0
  static String getLength(String dat) {
    //转换成十六进制
    String hexLength = (dat.length ~/ 2).toRadixString(16);
    if (hexLength.length < 2) {
      return "0" + hexLength;
    } else {
      return hexLength;
    }
  }

  static int getCode(List<int> buf) {
    int N = buf.length;
    int result = buf[0x0];
    for (int i = 0x1; i < N; i = i + 0x1) {
      result = (buf[i] ^ result);
    }
    return (result ^ 0xA6); //result
  }

  //将蓝牙返回数据转换成十六进制的字符串
  static String byteListConvertHex(List<int> dataByte) {
    Uint8List uint8list = Uint8List.fromList(dataByte);
    return Hex.formatBytesAsHexString(uint8list).toUpperCase();
  }

  //将十六进制字符串转换成byte数组
  static List<int> hexConvertList(String hexString) {
    var pre = '0';
    if (hexString.length % 2 == 1) {
      hexString = pre + hexString;
    }
    List<int> list = [];
    var uint8list = Hex.createUint8ListFromHexString(hexString);
    list.addAll(uint8list);
    return list;
  }
}
