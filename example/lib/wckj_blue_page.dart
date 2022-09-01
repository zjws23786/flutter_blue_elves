import 'package:flutter/material.dart';
import 'package:flutter_blue_elves/flutter_blue_elves.dart';
import 'package:flutter_blue_elves_example/personal_entity.dart';
import 'package:flutter_blue_elves_example/string_utils.dart';
import 'package:flutter_blue_elves_example/time_utils.dart';
import 'package:flutter_blue_elves_example/wckj_ble_utils.dart';

import 'hex.dart';

class WckjBluePage extends StatefulWidget {
  final String? _macAddress;
  final String? _name;
  final Device _device;

  const WckjBluePage(this._name, this._macAddress, this._device, {Key? key})
      : super(key: key);

  @override
  State<WckjBluePage> createState() => _WckjBluePageState();
}

class _WckjBluePageState extends State<WckjBluePage> {
  late DeviceState _deviceState;
  String? mUuid_service;
  String? mUuid_charact;
  String bleResponseData = ""; //蓝牙响应回来数据
  String sendHandShakeCmd = "";
  int command = 0; //和蓝牙通信步骤
  String? blueId; //蓝牙芯片ID
  bool isConnectSuccess = false;
  String? keyPwd = "";
  int? onLineTime = 24;
  String? serverTime;
  int? startTime;

  @override
  void dispose() {
    widget._device.disConnect();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // widget._device.connect(connectTimeout: 10000);
    widget._device.stateStream.listen((event) {
      switch (event) {
        case DeviceState.disconnected: //未连接
          print("hjz  未连接");
          break;
        case DeviceState.disConnecting: //正在断开连接
          break;
        case DeviceState.connecting: //连接中
          print("hjz  正在连接");
          break;
        case DeviceState.connected: //已连接
          if(isConnectSuccess)return;
          print("hjz  连接成功了");
          isConnectSuccess = true;
          // if (!widget._device.isWatchingRssi) widget._device.startWatchRssi();
          widget._device.discoveryService();
          break;
        case DeviceState.connectTimeout: //连接超时
          print("hjz  连接失败");
          break;
        case DeviceState.initiativeDisConnected: //主动去断开连接
          print("hjz  断开蓝牙");
          break;
        case DeviceState.destroyed: //已销毁
          break;
      }
    });
    widget._device.serviceDiscoveryStream.listen((bleService) {
      String serviceUuid = bleService.serviceUuid;
      print("serviceUuid=$serviceUuid");
      if (serviceUuid == WCKJBleUtils.WCKJ_SERVICE_UUID) {
        List<BleCharacteristic> characteristics = bleService.characteristics;
        for (int i = 0; i < characteristics.length; i++) {
          BleCharacteristic bleCharacteristic = characteristics[i];
          String uuid_charact = bleCharacteristic.uuid;
          if (uuid_charact == WCKJBleUtils.WCKJ_CHARACT_UUID) {
            print("hjz 找到WCKJ 匹对UUID蓝牙的特征 蓝牙连接成功");
            mUuid_service = bleService.serviceUuid;
            mUuid_charact = uuid_charact;
            widget._device
                .setNotify(mUuid_service!, mUuid_charact!, true)
                .then((result) {
              print(
                  "setNotify  setNotify=$mUuid_service! uuid_charact=$mUuid_charact result=$result");
            });
            return;
          }
        }
      }
    });

    widget._device.deviceSignalResultStream.listen((event) {
      if (event.data != null && event.data!.isNotEmpty) {
        print("event.type=${event.type}");
        if(event.type == DeviceSignalType.characteristicsWrite){
          return;
        }
        String currentStr = WCKJBleUtils.toHexStr(event.data!);
        bleResponseData = bleResponseData + currentStr;
        print("hjz 蓝牙响应回来数据：$bleResponseData");
        print("hjz command=$command");
        if (!bleResponseData.startsWith("EA")) {
          bleResponseData = "";
          return;
        }
        print("蓝牙响应回来指令是否完成=${WCKJBleUtils.isDataComplete(bleResponseData)}");
        if(WCKJBleUtils.isDataComplete(bleResponseData)){
          if (bleResponseData.substring(12, 16) == '15A5') {
            blueId = bleResponseData.substring(4, 12);
            sendHandShakeCmd = WCKJBleUtils.sendHandShake(bleResponseData);
            print("发送握手指令$sendHandShakeCmd");
            command = 0;
            widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                Hex.createUint8ListFromHexString(sendHandShakeCmd));
            bleResponseData = "";
          } else {
            switch (command) {
              case 0: //处理握手
                if (bleResponseData.substring(12,16) == "15AA") {
                  //握手成功
                  print("握手成功");
                  bleResponseData = "";
                  command = 1;
                  String message = WCKJBleUtils.readKeyIdCommand();
                  print("message=" + message);
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                }
                break;
              case 1:
                print("解析读取设备id=$bleResponseData");
                String result =
                WCKJBleUtils.readKeyIdMessage(bleResponseData);
                bleResponseData = "";
                if (result.contains("成功")) {
                  print("读取readKeyIdMessage成功了");
                  WCKJBleUtils.MyCode =
                      WCKJBleUtils.dataToByte("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
                  keyPwd = "";
                  onLineTime = 8760;
                  serverTime = "2022-08-30 11:13:52";
                  startTime = (TimeUtils.dateToLong(serverTime!) / 1000).toInt();
                  command = 2;
                  ///读取开门记录
                  String message = WCKJBleUtils.readRecordCommand();
                  print("发送读取开门记录指令$message");
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                }
                break;
              case 2:
                String result = WCKJBleUtils.readLockRecordMessage(bleResponseData);
                print("result=" + result);
                bleResponseData = "";
                if (result.contains("暂无最新记录")) {
                  ///同步时钟
                  command = 7;
                  print("同步时钟");
                  String message = WCKJBleUtils.setDeviceTime(serverTime!);
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                } else if (result.contains("成功")) {
                  String message = WCKJBleUtils.readRecordCommand();
                  print("发送读取开门记录指令$message");
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                } else {
                  // eventBus.fire(BleOperationEntity(showInfo: "提取开门记录失败",isError: true));
                }
                break;
              case 3:
                bleResponseData = "";
                print("同步人员信息中");
                command = 4;
                String userKeyId = '124265';
                String userKeyPassword = '12341234';
                List<PersonalEntity> localArrayList = [];
                PersonalEntity localPersonalDto = new PersonalEntity(
                    "0000",
                    userKeyId,
                    userKeyPassword);
                localArrayList.add(localPersonalDto);
                String message = WCKJBleUtils.setGroupPersonCommand(localArrayList);
                widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                    Hex.createUint8ListFromHexString(message));
                break;
              case 4:
                String result = WCKJBleUtils.readGroupPersonMessage(bleResponseData);
                if(result.contains("成功")){
                  print("同步人员信息成功");
                }else{
                  print("同步人员信息失败");
                }
                break;
              case 7:
                String result =
                WCKJBleUtils.readReturnMessage(bleResponseData);
                bleResponseData = "";
                if (result.contains("成功")) {
                  print("同步时钟成功");
                  command = 9;
                  String message = WCKJBleUtils.sendReadLockCommand();
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                } else {
                  print("同步时钟失败");
                }
                break;
              case 9:
                String result = WCKJBleUtils.readElectricMessage(bleResponseData);
                bleResponseData = "";
                if(result.contains("读取成功")){
                  print("清除权限中...");
                  command = 3;
                  String message = WCKJBleUtils.deleteAllAuth();
                  print("清除权限指令：$message");
                  widget._device.writeData(mUuid_service!, mUuid_charact!, false,
                      Hex.createUint8ListFromHexString(message));
                }
                break;
            }
          }
        }

      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._name ?? ""),
        centerTitle: true,
      ),
    );
  }
}
