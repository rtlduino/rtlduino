//
//  SimpleConfig.m
//  SimpleConfig
//
//  Created by Realsil on 14/11/6.
//  Copyright (c) 2014年 Realtek. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import "SimpleConfig.h"

@implementation SimpleConfig
@synthesize config_list, discover_list;

int isTriggerSend = 0;
int g_device_num = 0;

-(id)init
{
    NSLog(@"simple config init");
    m_mode = MODE_INIT;
    m_current_pattern = -1;
#if SC_SUPPORT_2X2
    m_config_duration = -1;
#endif
#if SC_CONFIG_QC_TEST
    m_model = -1;
    m_mix_model_max_duration = -1;
#endif
    m_shouldStop = false;
    m_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(timerHandler:) userInfo:nil repeats:YES];
    config_list = [[NSMutableArray alloc] initWithObjects:nil];
    discover_list = [[NSMutableArray alloc] initWithObjects:nil];
    m_idev_model = [[NSString alloc] initWithString:[self platformString]];
    NSLog(@"iDevice: %@", m_idev_model);
    
    return [super init];
}

-(void)dealloc
{
#ifdef ARC
    [config_list dealloc];
    [discover_list dealloc];
#endif
    for (int i=0; i<SC_MAX_PATTERN_NUM; i++) {
        if (m_pattern[i]!=nil) {
            [m_pattern[i] rtk_sc_close_sock];
#ifdef ARC
            [m_pattern[i] dealloc];
#endif
        }
    }
#ifdef ARC
#if SC_SUPPORT_2X2
    [m_ssid release];
    [m_password release];
    [m_pin release];
    [m_idev_model release];
#endif
#endif
    // must stop timer!
    [m_timer invalidate];
#ifdef ARC
    [super dealloc];
#endif
}

-(void)rtk_sc_close_sock
{
    NSLog(@"simpleconfig: rtk_sc_close_sock");
    if ([m_timer isValid]) {
        [m_timer invalidate];
    }
    
    [m_pattern[m_current_pattern] rtk_sc_close_sock];
    
#if SC_SUPPORT_2X2
    if (m_current_pattern!=PATTERN_FOUR && m_config_duration>SC_PATTERN_DEF_SWITCH_THRESHOLD) {
        [m_pattern[PATTERN_FOUR] rtk_sc_close_sock];
    }
#endif
}

-(void)rtk_sc_reopen_sock
{
    NSLog(@"simpleconfig:rtk_sc_reopen_sock");
    if (m_timer==nil) {
        m_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(timerHandler:) userInfo:nil repeats:YES];
    }
    [m_pattern[m_current_pattern] rtk_sc_reopen_sock];
    
#if SC_SUPPORT_2X2
    if (m_current_pattern!=PATTERN_FOUR && m_config_duration>SC_PATTERN_DEF_SWITCH_THRESHOLD) {
        [m_pattern[PATTERN_FOUR] rtk_sc_reopen_sock];
    }
#endif
}

-(void)rtk_sc_config_set_devNum: (int)device_num
{
    g_device_num = device_num;
    [m_pattern[m_current_pattern] rtk_pattern_set_dev_num:device_num];

}

-(int)rtk_sc_config_start: (NSString *)ssid psw:(NSString *)password pin:(NSString *)pin
{
    // actually we don't send here. It's timer handler's duty to send
    int ret;
    
    NSLog(@"rtk_sc_start_config, m_idev_model=%@",m_idev_model);

    // base on the PIN input and device type, decide to use Pattern
#if SC_CONFIG_QC_TEST
    // the following is for testing
    switch (m_model) {
        case SC_MODEL_2:
            if (pin==nil || [pin isEqualToString:@""] || [pin intValue]==0 || [pin isEqualToString:PATTERN_DEF_PIN]){
                // no PIN --> P2
                m_pattern[PATTERN_TWO] = [[PatternTwo alloc] init:SC_USE_ENCRYPTION];
                m_current_pattern = PATTERN_TWO;
                pin = PATTERN_DEF_PIN;
                m_pattern[PATTERN_THREE] = nil;
            }else{
                // have PIN --> P3
                m_pattern[PATTERN_THREE] = [[PatternThree alloc] init:SC_USE_ENCRYPTION];
                m_current_pattern = PATTERN_THREE;
                m_pattern[PATTERN_TWO] = nil;
            }
            break;
            
        case SC_MODEL_3:
            if (pin==nil || [pin isEqualToString:@""] || [pin intValue]==0){
                // no PIN --> P2
                m_pattern[PATTERN_TWO] = [[PatternTwo alloc] init:SC_USE_ENCRYPTION];
                m_current_pattern = PATTERN_TWO;
                pin = PATTERN_DEF_PIN;
                m_pattern[PATTERN_THREE] = nil;
            }else{
                // have PIN --> P3
                m_pattern[PATTERN_THREE] = [[PatternThree alloc] init:SC_USE_ENCRYPTION];
                m_current_pattern = PATTERN_THREE;
                m_pattern[PATTERN_TWO] = nil;
            }
            m_pattern[PATTERN_FOUR] = [[PatternFour alloc] init:SC_USE_ENCRYPTION];
            break;
            
        case SC_MODEL_1:
        default:
            //NSLog(@"SC_MODEL_1");
            m_current_pattern = PATTERN_FOUR;
            m_pattern[m_current_pattern] = [[PatternFour alloc] init:SC_USE_ENCRYPTION];
            break;
    }
#else
    if ([m_idev_model isEqualToString:@"iPad Mini2"])
    {
        m_current_pattern = PATTERN_FOUR;
        m_pattern[PATTERN_FOUR] = [[PatternFour alloc] init:SC_USE_ENCRYPTION];
    }else{
        if (pin==nil || [pin isEqualToString:@""] || [pin intValue]==0){
            m_pattern[PATTERN_TWO] = [[PatternTwo alloc] init:SC_USE_ENCRYPTION];
            m_current_pattern = PATTERN_TWO;
            pin = PATTERN_DEF_PIN;
            m_pattern[PATTERN_THREE] = nil;
        }
        else{
            m_pattern[PATTERN_THREE] = [[PatternThree alloc] init:SC_USE_ENCRYPTION];
            m_current_pattern = PATTERN_THREE;
            m_pattern[PATTERN_TWO] = nil;
        }
        // init PATTERN 4, build its profile when needed!
        m_pattern[PATTERN_FOUR] = [[PatternFour alloc] init:SC_USE_ENCRYPTION];
    }
#endif
    
    // set profile
    //NSLog(@"simpleconfig: set pattern %d", m_current_pattern+1);
    ret = [m_pattern[m_current_pattern] rtk_pattern_build_profile:ssid psw:password pin:pin];
    if (ret==RTK_FAILED)
        return ret;
    
    [config_list removeAllObjects];
    m_shouldStop = false;
    m_mode = MODE_CONFIG;
#if SC_SUPPORT_2X2
    m_config_duration = 0;
#ifdef ARC
    if(ssid!=nil)
        m_ssid = [[[NSString alloc] initWithString:ssid] retain];
    else
        m_ssid = nil;
    m_password = [[[NSString alloc] initWithString:password] retain];
    m_pin = [[[NSString alloc] initWithString:pin] retain];
#endif
#endif
    return ret;
}

-(void)rtk_sc_config_stop
{
    m_shouldStop = true;
    NSLog(@"Close socket here!");
    //[m_pattern[m_current_pattern] rtk_sc_close_sock];
    m_mode = MODE_INIT;
}

-(int)rtk_sc_discover_start:(unsigned int)scan_time
{
    int ret = RTK_FAILED;
    // TODO
    return ret;
}

-(int) rtk_sc_control_start:(NSString *)client_mac type:(unsigned char)control_type
{
    int ret = RTK_FAILED;
    // TODO
    return ret;
}

-(unsigned int)rtk_sc_get_mode
{
    return m_mode;
}

#if SC_CONFIG_QC_TEST
-(void)rtk_sc_set_sc_model: (unsigned int) model duration: (unsigned int) duration
{
    m_model = model;
    if (m_model==SC_MODEL_3)
        // set max duration only under mix model
        m_mix_model_max_duration = duration;
}
#endif

/*-----------Private Funcs-------------*/
-(BOOL)haveSameMac:(unsigned char *)mac1 mac2:(unsigned char *)mac2
{
    if(mac1==nil || mac2==nil)
        return false;
    
    for(int i=0; i<MAC_ADDR_LEN; i++){
        if(mac1[i]==mac2[i])
            continue;
        else
            return false;
    }
    return true;
}

- (NSString *) platformString{
    // Gets a string with the device model  6
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
    free(machine);
    
    NSLog(@"platform: %@", platform);
    if ([platform isEqualToString:@"iPhone1,1"])    return @"iPhone 2G";
    if ([platform isEqualToString:@"iPhone1,2"])    return @"iPhone 3G";
    if ([platform isEqualToString:@"iPhone2,1"])    return @"iPhone 3GS";
    if ([platform isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
    if ([platform isEqualToString:@"iPhone3,2"])    return @"iPhone 4";
    if ([platform isEqualToString:@"iPhone3,3"])    return @"iPhone 4 (CDMA)";
    if ([platform isEqualToString:@"iPhone4,1"])    return @"iPhone 4S";
    if ([platform isEqualToString:@"iPhone5,1"])    return @"iPhone 5";
    if ([platform isEqualToString:@"iPhone5,2"])    return @"iPhone 5 (GSM+CDMA)";
    
    if ([platform isEqualToString:@"iPod1,1"])      return @"iPod Touch (1 Gen)";
    if ([platform isEqualToString:@"iPod2,1"])      return @"iPod Touch (2 Gen)";
    if ([platform isEqualToString:@"iPod3,1"])      return @"iPod Touch (3 Gen)";
    if ([platform isEqualToString:@"iPod4,1"])      return @"iPod Touch (4 Gen)";
    if ([platform isEqualToString:@"iPod5,1"])      return @"iPod Touch (5 Gen)";
    
    if ([platform isEqualToString:@"iPad1,1"])      return @"iPad";
    if ([platform isEqualToString:@"iPad1,2"])      return @"iPad 3G";
    if ([platform isEqualToString:@"iPad2,1"])      return @"iPad 2 (WiFi)";
    if ([platform isEqualToString:@"iPad2,2"])      return @"iPad 2";
    if ([platform isEqualToString:@"iPad2,3"])      return @"iPad 2 (CDMA)";
    if ([platform isEqualToString:@"iPad2,4"])      return @"iPad 2";
    if ([platform isEqualToString:@"iPad2,5"])      return @"iPad Mini (WiFi)";
    if ([platform isEqualToString:@"iPad2,6"])      return @"iPad Mini";
    if ([platform isEqualToString:@"iPad2,7"])      return @"iPad Mini (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad3,1"])      return @"iPad 3 (WiFi)";
    if ([platform isEqualToString:@"iPad3,2"])      return @"iPad 3 (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad3,3"])      return @"iPad 3";
    if ([platform isEqualToString:@"iPad3,4"])      return @"iPad 4 (WiFi)";
    if ([platform isEqualToString:@"iPad3,5"])      return @"iPad 4";
    if ([platform isEqualToString:@"iPad3,6"])      return @"iPad 4 (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad4,4"])      return @"iPad Mini2";
    if ([platform isEqualToString:@"i386"])         return @"Simulator";
    if ([platform isEqualToString:@"x86_64"])       return @"Simulator";
    
    return platform;
}

-(void)update_config_list
{
    // update config_list
    NSMutableArray *recv_list = [m_pattern[m_current_pattern] rtk_pattern_get_config_list];
    
    struct dev_info config_dev;
    NSValue *config_dev_val = nil;
    int i = 0, getIP_deviceNum=0;
    
    [config_list removeAllObjects];
    for (i=0; i<(int)[recv_list count]; i++) {
        [config_list addObject:[recv_list objectAtIndex:i]];
    }
    
    if ([config_list count]>0) {
        
        for (i=0; i<[config_list count]; i++) {
            config_dev_val = [recv_list objectAtIndex:i];
            [config_dev_val getValue:&config_dev];
            if (config_dev.ip!=0) {
                getIP_deviceNum++;
            }
        }
    }
    
}

- (NSMutableArray *)getList_forConfirm
{
    return [m_pattern[m_current_pattern] rtk_pattern_get_config_list];
}

-(void)timerHandler:(id)sender
{
    if (m_current_pattern<0 || m_current_pattern>=SC_MAX_PATTERN_NUM) {
        return ;
    }
    int status = RTK_FAILED;
    unsigned int pattern_mode;
#if SC_SUPPORT_2X2
#if SC_CONFIG_QC_TEST
    if (m_model==SC_MODEL_3 && m_config_duration>m_mix_model_max_duration && m_current_pattern!=PATTERN_FOUR)
#else
    if (m_config_duration>SC_PATTERN_DEF_SWITCH_THRESHOLD && m_current_pattern!=PATTERN_FOUR)
#endif
    {
        // close previous socket
        [m_pattern[m_current_pattern] rtk_sc_close_sock];
        m_current_pattern=PATTERN_FOUR;
        [m_pattern[m_current_pattern] rtk_pattern_build_profile:m_ssid psw:m_password pin:m_pin];
        NSLog(@"m_current_pattern: %d", m_current_pattern);
        NSLog(@"mode:%d", [m_pattern[m_current_pattern] rtk_sc_get_mode]);
    }
#endif
    pattern_mode = [m_pattern[m_current_pattern] rtk_sc_get_mode];
    
    //NSLog(@"SimpleConfig(curr_pattern:%d) mode: %d; Pattern mode: %d", m_current_pattern, m_mode, pattern_mode);
    
    switch (m_mode) {
        case MODE_INIT:
            //NSLog(@"Standing by...");
            break;
            
        case MODE_CONFIG:
            if(m_shouldStop==false){
                //NSLog(@"SimpleConfig(curr_pattern:%d) mode: %d; Pattern mode: %d", m_current_pattern, m_mode, pattern_mode);
                // upper layer allows configuring
                if (pattern_mode==MODE_CONFIG) {
                    // send config profile
#if SC_SUPPORT_2X2
                    // update duration
                    m_config_duration++;
                    {
                        // duration less than SC_PATTERN_SWITCH_THRESHOLD
                        if (m_current_pattern==PATTERN_FOUR) {
                            status = [m_pattern[m_current_pattern] rtk_pattern_send:[NSNumber numberWithInt:1]];
                        }else{
                            status = [m_pattern[m_current_pattern] rtk_pattern_send:[NSNumber numberWithInt:SC_SEND_ROUND_PER_SEC]];
                        }
                    }
#endif
                    if (status == RTK_FAILED) {
                        NSLog(@"4rr1");
                        m_mode = MODE_ALERT;
                    }
                }else if(pattern_mode==MODE_WAIT_FOR_IP || pattern_mode==MODE_INIT){
                    m_mode = (pattern_mode==MODE_INIT)? MODE_INIT:MODE_WAIT_FOR_IP;

                    NSLog(@"###1 device num: %lu ###",(unsigned long)[[m_pattern[m_current_pattern] rtk_pattern_get_config_list] count]);
                    
                    // update config_list
                    [self update_config_list];

                }
                else{
                    NSLog(@"Err2");
                    m_mode = MODE_ALERT;
                }
            }else{
                // upper layer orders to stop, reset m_shouldStop flag
                m_shouldStop = false;
                m_mode = MODE_INIT;
            }
            break;
            
        case MODE_WAIT_FOR_IP:
            
            if(m_current_pattern==PATTERN_FOUR) {
                [m_pattern[m_current_pattern] rtk_pattern_send:[NSNumber numberWithInt:1]];
            }
            
            if(pattern_mode==MODE_WAIT_FOR_IP){
                
                // update config_list
                [self update_config_list];
                NSLog(@"###2 device num: %lu ###",(unsigned long)[config_list count]);
                
            }else if(pattern_mode==MODE_INIT){
                
                // update config_list
                [self update_config_list];
                NSLog(@"###3 device num: %lu ### Finish",(unsigned long)[config_list count]);
                
            }
            
            break;
            
        case MODE_DISCOVER:
            break;
            
        case MODE_ALERT:
            [self showAlert];
            m_mode = MODE_INIT;
#if SC_SUPPORT_2X2
            m_config_duration = -1;
#endif
            break;
            
        default:
            NSLog(@"Error UI mode!");
            break;
    }
}

-(void)showAlert
{
    if (m_mode == MODE_ALERT) {
        // garantee only MODE_ALERT can do this
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"Error" message:m_error delegate:self cancelButtonTitle:@"Stop" otherButtonTitles:nil, nil];
        [alert show];
    }
}
@end
