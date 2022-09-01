#import "FlutterBlueElvesPlugin.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "Device.h"
#define CHANNEL_METHOD @"flutter_blue_elves/method"
#define EVENT_CHANNEL @"flutter_blue_elves/event"

@interface FlutterBlueElvesPlugin()<CBCentralManagerDelegate,FlutterStreamHandler>
@property (nonatomic,strong,readwrite) FlutterEventSink myEventSink;//flutter中订阅了接收我发送的消息的观察者,因为ios取消监听的回调函数没有传eventSink对象进来
@property(strong,nonatomic,readwrite)CBCentralManager *centralManager;//本地蓝牙管理
@property(strong,nonatomic,readwrite)NSMutableDictionary<NSString*,CBPeripheral *> *scanDeviceCaches;
@property(strong,nonatomic,readwrite)NSMutableDictionary<NSString*,CBPeripheral *> *hideConnectedDeviceCaches;
@property(strong,nonatomic,readwrite)NSMutableDictionary<NSString*,Device*> *devicesMap;
@property(assign,nonatomic,readwrite)BOOL isFixScan;
@end

@implementation FlutterBlueElvesPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:CHANNEL_METHOD
                                     binaryMessenger:[registrar messenger]];
    FlutterBlueElvesPlugin* instance = [[FlutterBlueElvesPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    FlutterEventChannel *eventChannel = [FlutterEventChannel eventChannelWithName:EVENT_CHANNEL binaryMessenger:[registrar messenger]];
    [eventChannel setStreamHandler:instance];
}

-(instancetype)init{
    self = [super init];
    self.centralManager=[[CBCentralManager alloc]initWithDelegate:self queue:nil];
    self.devicesMap=[NSMutableDictionary new];
    self.scanDeviceCaches=[NSMutableDictionary new];
    self.hideConnectedDeviceCaches=[NSMutableDictionary new];
    self.isFixScan=NO;
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"checkBluetoothState" isEqualToString:call.method]) {//如果是获取蓝牙状态
        if(self.centralManager.state==CBManagerStateUnknown)
            result([NSNumber numberWithInt:0]);
        else if(self.centralManager.state==CBManagerStateResetting)
            result([NSNumber numberWithInt:1]);
        else if(self.centralManager.state==CBManagerStateUnsupported)
            result([NSNumber numberWithInt:2]);
        else if(self.centralManager.state==CBManagerStateUnauthorized)
            result([NSNumber numberWithInt:3]);
        else if(self.centralManager.state==CBManagerStatePoweredOff)
            result([NSNumber numberWithInt:4]);
        else if(self.centralManager.state==CBManagerStatePoweredOn)
            result([NSNumber numberWithInt:5]);
    } else if([@"startScan" isEqualToString:call.method]){//如果是扫描设备
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        [self scanDevice:[dataMap objectForKey:@"isAllowDuplicates"] timeout:[[dataMap objectForKey:@"timeout"] intValue] isFix:NO];
        result(nil);
    }else if([@"stopScan" isEqualToString:call.method]){//如果是停止扫描
        [self stopScan];
        result(nil);
    }else if([@"getHideConnected" isEqualToString:call.method]){//如果是获取其他应用连接上的设备信息
        NSArray<CBPeripheral *> * hideConnectedDevices=[self.centralManager retrieveConnectedPeripheralsWithServices:@[[CBUUID UUIDWithString:@"1800"],[CBUUID UUIDWithString:@"1801"]]];
        [self.hideConnectedDeviceCaches removeAllObjects];//先把之前缓存的设备结果列表清空
        NSMutableArray<NSMutableDictionary<NSString*,id>*> *hideDeviceMsgList=[NSMutableArray new];
        for (CBPeripheral * device in hideConnectedDevices) {
            if([self.devicesMap objectForKey:[device.identifier UUIDString]]==nil){
                [self.hideConnectedDeviceCaches setValue:device forKey:[device.identifier UUIDString]];
                NSMutableDictionary<NSString*,id>* deviceMsg=[[NSMutableDictionary alloc] initWithCapacity:3];
                [deviceMsg setValue:[device.identifier UUIDString] forKey:@"id"];
                [deviceMsg setValue:device.name forKey:@"name"];
                [deviceMsg setValue:@[] forKey:@"uuids"];
                [hideDeviceMsgList addObject:deviceMsg];
            }
        }
        result(hideDeviceMsgList);
    }else if([@"connect" isEqualToString:call.method]){//如果是去连接设备
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        BOOL isFromScan=[[dataMap objectForKey:@"isFromScan"] boolValue];
        CBPeripheral * cache=isFromScan==YES?[self.scanDeviceCaches objectForKey:deviceId]:[self.hideConnectedDeviceCaches objectForKey:deviceId];
        if(cache!=nil){//如果这个id存在的话
            if(isFromScan==YES)
                [self.scanDeviceCaches removeObjectForKey:deviceId];
            else
                [self.hideConnectedDeviceCaches removeObjectForKey:deviceId];
            Device * toConnectDevice=[self.devicesMap objectForKey:deviceId];
            if(toConnectDevice==nil){//如果本来就有这个设备就不用再创一个了
                toConnectDevice=[[Device alloc] init:deviceId centralManager:self.centralManager peripheral:cache pluginInstance:self rssi:[dataMap objectForKey:@"rssi"]];
                [self.devicesMap setValue:toConnectDevice forKey:deviceId];
            }
            [toConnectDevice connectDevice:[[dataMap objectForKey:@"timeout"] intValue]];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"reConnect" isEqualToString:call.method]){//如果是去重连设备
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device connectDevice:[[dataMap objectForKey:@"timeout"] intValue]];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"disConnect" isEqualToString:call.method]){//如果是去断开设备连接
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device initiativeDisConnect];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"discoverService" isEqualToString:call.method]){//如果是去发现服务
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device discoverService];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"setNotify" isEqualToString:call.method]){//如果是去开启或者关闭notify
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device setNotifyCharacteristic:[dataMap objectForKey:@"serviceUuid"] characteristicUuid:[dataMap objectForKey:@"characteristicUuid"] isEnable:[[dataMap objectForKey:@"isEnable"] boolValue]];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"readData" isEqualToString:call.method]){//如果是使用读特征值向设备读取数据
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device readDataToDevice:[dataMap objectForKey:@"serviceUuid"] characteristicUuid:[dataMap objectForKey:@"characteristicUuid"]];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"writeData" isEqualToString:call.method]){//如果是使用写特征值向设备写入数据
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            FlutterStandardTypedData * flutterData=[dataMap objectForKey:@"data"];
            [device writeDataToDevice: [dataMap objectForKey:@"serviceUuid"] characteristicUuid:[dataMap objectForKey:@"characteristicUuid"] isNoResponse:[[dataMap objectForKey:@"isNoResponse"] boolValue] data:flutterData.data];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"readDescriptorData" isEqualToString:call.method]){//如果是使用特征值描述向设备读取数据
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device readDescriptorDataToDevice:[dataMap objectForKey:@"serviceUuid"] characteristicUuid:[dataMap objectForKey:@"characteristicUuid"] descriptorUuid:[dataMap objectForKey:@"descriptorUuid"]];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"writeDescriptorData" isEqualToString:call.method]){//如果是使用特征值描述向设备写入数据
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            FlutterStandardTypedData * flutterData=[dataMap objectForKey:@"data"];
            [device writeDescriptorDataToDevice:[dataMap objectForKey:@"serviceUuid"] characteristicUuid:[dataMap objectForKey:@"characteristicUuid"] descriptorUuid:[dataMap objectForKey:@"descriptorUuid"] data:flutterData.data];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else if([@"watchRssi" isEqualToString:call.method]){//如果是开始监听rssi的变化
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil)//如果这个id存在的话
            result([NSNumber numberWithBool:[device watchRssi:[[dataMap objectForKey:@"isStart"] boolValue]]]);
        result([NSNumber numberWithBool:NO]);
    }else if([@"destroy" isEqualToString:call.method]){//如果是销毁对象
        NSDictionary<NSString *,id> * dataMap=call.arguments;
        NSString * deviceId=[dataMap objectForKey:@"id"];
        Device * device=[self.devicesMap objectForKey:deviceId];
        if(device!=nil){//如果这个id存在的话
            [device destroy];
            [self.devicesMap removeObjectForKey:deviceId];
            result([NSNumber numberWithBool:YES]);
        }
        result([NSNumber numberWithBool:NO]);
    }else
        result(FlutterMethodNotImplemented);//没有此方法
}

//扫描设备
- (void)scanDevice:(NSNumber *)isAllowDuplicates timeout:(int) timeout isFix:(BOOL) isFix{
    [self stopScan];//先停止当前扫描
    if(!isFix)
        [self.scanDeviceCaches removeAllObjects];//先把之前缓存的扫描设备结果列表清空
    self.isFixScan=isFix;
    NSDictionary *option = [NSDictionary dictionaryWithObject:isAllowDuplicates forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    [self.centralManager scanForPeripheralsWithServices:nil options:option];//开始扫描
    [self performSelector:@selector(scanTimeoutCallback) withObject:nil afterDelay:timeout];//设置多少秒后停止扫描
}

//停止扫描
-(void)stopScan{
    [self.centralManager stopScan];// 停止扫描
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scanTimeoutCallback) object:nil];//取消扫描超时的定时任务
}

//CBCentralManagerDelegate一定要有这个方法
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch(central.state){
        case CBManagerStatePoweredOff://如果蓝牙被关闭了
            for (NSString * deviceId in self.devicesMap) {//就要将所有的设备对象都断开连接
                Device * device=[self.devicesMap objectForKey:deviceId];
                if(device.state==2){//如果是已经连接的设备才要去断开连接
                    [device notifyConnectState:0];//通知设备对象连接断开了
                    NSDictionary<NSString *,id> * result=@{@"eventName":@"disConnected",@"id":deviceId};//因为NSDictionary不可改变，所以一定要这样初始化
                    [self sendDataToFlutter:result];
                }
            }
            break;
        case CBManagerStatePoweredOn://如果蓝牙重新打开
            [self scanDevice:[NSNumber numberWithBool:YES] timeout:10 isFix:YES];//进行修复扫描
            break;
        default:break;
    }
}

//扫描设备列表回调
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(nonnull CBPeripheral *)peripheral advertisementData:(nonnull NSDictionary<NSString *,id> *)advertisementData RSSI:(nonnull NSNumber *)RSSI{
    if(self.isFixScan==NO){//正常扫描才要做这些
        NSString* currentId=[peripheral.identifier UUIDString];//使用设备对象uuid来作为唯一识别的key
        [self.scanDeviceCaches setValue:peripheral forKey:currentId];//将扫描到的设备对象缓存
        NSData* muData=[advertisementData objectForKey:CBAdvertisementDataManufacturerDataKey];
        NSDictionary<NSNumber *,NSData*> * muDataMap;
        if(muData!=nil&&muData.length>2){
            int muKeyInt=0;
            NSData* muDataKeyByte=[muData subdataWithRange:NSMakeRange(0, 2)];
            [muDataKeyByte getBytes:&muKeyInt length:sizeof(muKeyInt)];
            muData=[muData subdataWithRange:NSMakeRange(2, muData.length-2)];
            muDataMap=[[NSDictionary alloc]
                       initWithObjectsAndKeys:
                       muData,[NSNumber numberWithInt:muKeyInt],nil];
        }
        NSArray<CBUUID*> *uuidArray  =[advertisementData objectForKey:CBAdvertisementDataServiceUUIDsKey];//整体是NSArrayM(数组类型)，里面的对象是CBUUID(CORE BLUETOOTH封装的对象)
        NSMutableArray<NSString*>* uuidStrs=[[NSMutableArray alloc]initWithCapacity:uuidArray.count];
        for (CBUUID* uuid in uuidArray) {
            [uuidStrs addObject:uuid.UUIDString];
        }
        NSString * localName=[advertisementData objectForKey:CBAdvertisementDataLocalNameKey];
        NSDictionary<NSString *,id> * result=@{@"eventName":@"scanResult",@"id":currentId,@"name":peripheral.name==nil?[NSNull null]:peripheral.name,@"localName":localName==nil?[NSNull null]:localName,@"rssi":RSSI,@"uuids":uuidStrs,@"manufacturerSpecificData":muDataMap==nil?[NSNull null]:muDataMap};//因为NSDictionary不可改变，所以一定要这样初始化
        [self sendDataToFlutter:result];
    }
}

//设备连接成功的回调
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSString * deviceId=[peripheral.identifier UUIDString];//获取连接成功设备对象uuid
    Device * device=[self.devicesMap objectForKey:deviceId];//获取自定义的设备对象
    if(device!=nil){
        [device notifyConnectState:1];
        NSDictionary<NSString *,id> * result=@{@"eventName":@"connected",@"id":deviceId,@"mtu":[NSNumber numberWithLong:[peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse]]};//因为NSDictionary不可改变，所以一定要这样初始化
        [self sendDataToFlutter:result];
    }
}

//连接失败的回调
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSString * deviceId=[peripheral.identifier UUIDString];//获取连接成功设备对象uuid
    Device * device=[self.devicesMap objectForKey:deviceId];//获取自定义的设备对象
    if(device!=nil)
        [device notifyConnectState:2];
}


// 设备连接断开的回调
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSString * deviceId=[peripheral.identifier UUIDString];//获取连接成功设备对象uuid
    Device * device=[self.devicesMap objectForKey:deviceId];//获取自定义的设备对象
    if(device!=nil&&device.state==2){//如果不是已经连接到设备收到这个消息，那就连接超时调用导致的
        [device notifyConnectState:0];
        NSDictionary<NSString *,id> * result=@{@"eventName":device.isInitiativeDisConnect==YES?@"initiativeDisConnected":@"disConnected",@"id":deviceId};//因为NSDictionary不可改变，所以一定要这样初始化
        [self sendDataToFlutter:result];
    }
}

//扫描超时调用的函数
-(void)scanTimeoutCallback{
    [self.centralManager stopScan];// 停止扫描
    if(self.isFixScan==NO){//正常扫描才要做这些
        NSDictionary<NSString *,id> * result=@{@"eventName":@"scanTimeout"};//因为NSDictionary不可改变，所以一定要这样初始化
        [self sendDataToFlutter:result];
    }
}

//连接超时时调用的函数
-(void)connectTimeout:(NSString *)deviceId{
    NSDictionary<NSString *,id> * result=@{@"eventName":@"connectTimeout",@"id":deviceId};//因为NSDictionary不可改变，所以一定要这样初始化
    [self sendDataToFlutter:result];
}

//获取服务的回调
-(void)discoverService:(NSString *)deviceId serviceUuid:(NSString *)serviceUuid characteristics:(NSArray<NSDictionary<NSString*,id>*> *)characteristics{
    NSDictionary<NSString *,id> * result=@{@"eventName":@"discoverService",@"id":deviceId,@"serviceUuid":serviceUuid,@"characteristic":characteristics};//因为NSDictionary不可改变，所以一定要这样初始化
    [self sendDataToFlutter:result];
}

//设备传回数据的回调
-(void)signalCallback:(short)type deviceId:(NSString *)deviceId uuid:(NSString*) uuid isSuccess:(BOOL)isSuccess data:(NSData *)data{
    NSDictionary<NSString *,id> * result=@{@"eventName":@"deviceSignal",@"id":deviceId,@"type":[NSNumber numberWithShort:type],@"uuid":uuid,@"isSuccess":[NSNumber numberWithBool:isSuccess],@"data":data==nil?[NSNull null]:[FlutterStandardTypedData typedDataWithBytes:data]};//因为NSDictionary不可改变，所以一定要这样初始化
    [self sendDataToFlutter:result];
}

//设备rssi变化的回调
-(void)rssiChangeCallback:(NSString *)deviceId newRssi:(NSNumber *) newRssi{
    NSDictionary<NSString *,id> * result=@{@"eventName":@"rssiChange",@"id":deviceId,@"newRssi":newRssi};//因为NSDictionary不可改变，所以一定要这样初始化
    [self sendDataToFlutter:result];
}

-(void)sendDataToFlutter:(id) data{//向flutter发送数据
    if(self.myEventSink!=nil)
        self.myEventSink(data);
}

#pragma mark - FlutterStreamHandler
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)eventSink{//当flutter向监听我们的channel时调用的函数
    self.myEventSink=eventSink;//设置观察者
    return nil;
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {//flutter取消对我们的监听时调用的函数
    self.myEventSink=nil;//删除观察者
    return nil;
}

@end
