#!/bin/bash

# 本脚本实现了携带VLANID进行PPPoE拨号中的VLAN接口和PPP接口配置
# 1、使用前一定要确保系统加载了802.1q的模块modprobe 8021q
# 2、确保/etc/ppp/chap-secrets和/etc/ppp/pap-secrets两个文件中有密码信息
# /etc/ppp/pap-secrets
# Secrets for authentication using PAP
# client	server	secret			IP addresses
#"39100422151"	*	"422151"
# /etc/ppp/chap-secrets
# Secrets for authentication using CHAP
# client	server	secret			IP addresses
#"39100422151"	*	"422151"
# 防止以为字符 sed -i 's/\r//g' dial

# 输出信息控制
PRINT=true
# 日志信息控制
LOG=true
# 报错信息控制
DEBUG=true

# 拨号的物理网卡
phyIf=em1
destDirPrefix=/etc/sysconfig/network-scripts/

# 创建PPP接口ifcfg-pppX时需要用到的账号信息
# 格式为 username-vlanid
# 这里面不需要密码，需要vlanid好确认使用哪个子接口
USERLISTFILE=username

# 管理口的默认网关和出接口，避免拨号上将默认路由改变
GATEWAY=192.168.0.3
MGTDEV=em2

# 测试IP，为了测试子接口到交换机的联通行，不写不会配置
# 写了会在接口生成10.233.VLANID.200的地址
TESTIPNET=10.233.
# PPP接口起始位置
PSTART=0

# 日志信息
logSuffix=`date --date='0 days ago' "+%Y%m%d%H%M%S"`
LOGFILE=/var/log/ppp/dial${logSuffix}.log

# 是否自动注入密码injection-target
INJECTION=true
# 从Username第几位开始获取，从0开始
PASSWORDLONG=5

mkdir -pv /var/log/ppp/

function print(){
  if $PRINT; then
    echo $1
  fi
}

function error(){
  # print "\033[31m$1\033[0m"
  print $1
}

function info(){
  # print "\033[36m$1\033[0m"
  print $1
}

function success(){
  # print "\033[32m$1\033[0m"
  print $1
}

function log(){
  if $LOG; then
    echo $1 >> ${LOGFILE}
  fi
}

function debug(){
  if $DEBUG; then
    echo $1
  fi
}



# 生成vlan接口文件
function makeVlanIf() {
  for((i=$1; i<=$2; i++))
  do
    destVlanIfFile=${destDirPrefix}ifcfg-${phyIf}.${i}
    print "生成文件VLAN $i接口文件: ${destVlanIfFile}"
    # echo "PHYSDEV=${phyIf}" >> ${destVlanIfFile}
    echo "DEVICE=${phyIf}.${i}" > ${destVlanIfFile}
  	echo "ONBOOT=yes" >> ${destVlanIfFile}
  	echo "BOOTPROTO=dhcp" >> ${destVlanIfFile}
  	echo "VLAN=yes" >> ${destVlanIfFile}
    echo "DEFROUTE=no" >> ${destVlanIfFile}
    # echo "TYPE=Vlan" >> ${destVlanIfFile}
  	# echo "ZONE=public" >> ${destVlanIfFile}
  	##
    
    # echo "NAME=${phyIf}.${i}" >> ${destVlanIfFile}
    # if [ $i -lt 10 ];then
    #   echo "HWADDR=e8:61:1f:1f:36:0${i}" >> ${destVlanIfFile}
    # else
    #   echo "HWADDR=e8:61:1f:1f:36:${i}" >> ${destVlanIfFile}
    # fi
    # echo "DEFROUTE=no" >> ${destVlanIfFile}
    # echo "BOOTPROTO=dhcp" >> ${destVlanIfFile}
    # if [ ${TESTIPNET} ]; then
    #   echo "IPADDR=${TESTIPNET}${i}.200" >> ${destVlanIfFile}
    #   echo "NETMASK=255.255.255.0" >> ${destVlanIfFile}
    # fi
     /sbin/ifdown ${phyIf}.${i}
     /sbin/ifup ${phyIf}.${i}
  done
}

# 生成ppp接口文件
function makePPPIf() {
  pppstr=`cat ${1}`
  array=(${pppstr//,/ })
  for i in ${!array[@]}
  do
    item=${array[$i]}
    items=(${item/-/ })
    username=(${items[0]})
    vlan=(${items[1]})
    j=$i
    destPPPIfFile=${destDirPrefix}ifcfg-ppp${j}
    print "生成文件PPP$i接口文件: ${destPPPIfFile}"
    echo "USERCTL=no" > ${destPPPIfFile}
  	echo "BOOTPROTO=dialup" >> ${destPPPIfFile}
  	echo "TYPE=xDSL" >> ${destPPPIfFile}
  	echo "ONBOOT=no" >> ${destPPPIfFile}
  	echo "FIREWALL=NONE" >> ${destPPPIfFile}
  	echo "PING=." >> ${destPPPIfFile}
  	echo "PPPOE_TIMEOUT=80" >> ${destPPPIfFile}
  	echo "LCP_FAILURE=3" >> ${destPPPIfFile}
  	echo "LCP_INTERVAL=20" >> ${destPPPIfFile}
  	echo "CLAMPMSS=1412" >> ${destPPPIfFile}
  	echo "CONNECT_POLL=6" >> ${destPPPIfFile}
  	echo "CONNECT_TIMEOUT=60" >> ${destPPPIfFile}
  	echo "DEFROUTE=no" >> ${destPPPIfFile}
  	echo "SYNCHRONOUS=no" >> ${destPPPIfFile}
  	echo "PEERDNS=no" >> ${destPPPIfFile}
  	echo "DEMAND=no" >> ${destPPPIfFile}
  	echo "PIDFILE=/var/run/pppoe-adsl-ppp${j}" >> ${destPPPIfFile}
  	echo "DEVICE=ppp${j}" >> ${destPPPIfFile}
  	echo "NAME=ppp${j}" >> ${destPPPIfFile}
  	echo "PROVIDER=DSLppp${j}" >> ${destPPPIfFile}
    echo "ETH=${phyIf}.${vlan}" >> ${destPPPIfFile}
    echo "USER=${username}" >> ${destPPPIfFile}

    echo "\"${username}\"     *    \"${username:${PASSWORDLONG}}\"" >> /etc/ppp/pap-secrets
    echo "\"${username}\"     *    \"${username:${PASSWORDLONG}}\"" >> /etc/ppp/chap-secrets
  done
}

function pppIfStatus() {
  # ip a | grep ppp${1} | grep inet #| awk '{print $7 "  " $2}' | tr -d "ppp" | sort -n
  /sbin/pppoe-status /etc/sysconfig/network-scripts/ifcfg-ppp${1}
}

function pppIfDown(){
  error "关闭ppp${1}接口..."
  /sbin/ifdown ppp$1
}

function pppIfUp(){
  info "启动ppp${1}接口..."
  #/sbin/ifup ppp10 && ip route del default && ip route add default via 192.168.0.2 dev ens2f1
  result=`/sbin/ifup ppp${1} && ip route del default && ip route add default via ${GATEWAY} dev ${MGTDEV}` #2>&1`
  res=`echo ${?}`
  username=`cat ${destDirPrefix}ifcfg-ppp${1} | grep USER= | awk -F= '{print $2}'`
  if [ ${res} -ne 0 ]; then
    print "ppp${1} ${username} fail"
    log "ppp${1} ${username} fail"
  else
    ip=`pppIfStatus ${1}`
    print "ppp${1} ${username} success, status: PPP${ip}"

    log "ppp${1} ${username} success, status: PPP${ip}"
  fi
  # debug "${res} ${result}"
}


 

case "$1" in
vlanif)
  mixvlan=$([ ! $2 ] && echo 2 || echo $2)
  maxvlan=$([ ! $3 ] && echo 2 || echo $3)
  if [ ${mixvlan} -gt ${maxvlan} ]; then
    error "VLAN ID最小号大于最大号，请查证后再试!!"
    exit 2
  fi
  makeVlanIf ${mixvlan} ${maxvlan}
  cat /proc/net/vlan/config
  ;;
pppif)
  userListFile=$([ ! $2 ] && echo ${USERLISTFILE} || echo $2)
  makePPPIf ${userListFile}
  ;;
ifdown)
  if [ ! $2 ]; then
    error "请输入需要关闭的接口号！！"
    exit 2
  fi
  pppIfDown $2
  ;;
rangeifdown)
  mix=$([ ! $2 ] && echo 0 || echo $2)
  max=$([ ! $3 ] && echo 0 || echo $3)
  if [ ${mix} -gt ${max} ]; then
    error "接口号最小号大于最大号，请查证后再试!!"
    exit 2
  fi
  for ((i=mix; i<=max; i++))
  do
    pppIfDown ${i}
  done
  ;;
allifdown)
  count=`ls /etc/sysconfig/network-scripts/ifcfg-ppp* | wc -l`
  for((i=${PSTART}; i<count; i++))
  do
    pppIfDown ${i}
  done
  ;;
ifrestart)
  if [ ! ${2} ]; then
    error "请输入需要重启的接口号！！"
    exit 2
  fi
  pppIfDown ${2}
  pppIfUp ${2}
  ;;
rangeifrestart)
  mix=$([ ! $2 ] && echo 0 || echo $2)
  max=$([ ! $3 ] && echo 0 || echo $3)
  if [ ${mix} -gt ${max} ]; then
    error "接口号最小号大于最大号，请查证后再试!!"
    exit 2
  fi
  for ((i=mix; i<=max; i++))
  do
      pppIfDown ${i}
      pppIfUp ${i}
  done
  ;;
allifrestart)
  count=`ls /etc/sysconfig/network-scripts/ifcfg-ppp* | wc -l`
  for((i=${PSTART}; i<count; i++))
  do
    {
      pppIfDown ${i}
      pppIfUp ${i}
    }&
  done
  ;;
ifstatus)
  info "PIf  IP"

  pppIfStatus ${2}
  ;;
*)
    echo $"Usage: $0 vlanif [min vlan id] [max vlan id] 配置vlan接口"
    echo $"    pppif  [min ppp id] [max ppp id] 配置PPP接口"
    echo $"    ifdown [pppid] 关闭某个PPP接口"
    echo $"    rangeifdown  [min ppp id] [max ppp id] 关闭一组PPP端口"
    echo $"    allifdown 关闭所有的PPP端口"
    echo $"    ifrestart [pppid] 重启一个PPP端口"
    echo $"    rangeifrestart  [min ppp id] [max ppp id] 重启一组PPP端口"
    echo $"    allifrestart 重启所有PPP端口"
    echo $"    ifstatus [pppid] 查看PPP端口信息"
    exit 2
esac


