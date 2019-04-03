#!/bin/sh

echo 1 > /proc/sys/net/ipv4/ip_forward
IPTABLES='/sbin/iptables'
$IPTABLES -t nat -A POSTROUTING -s 10.10.10.0/24 -j MASQUERADE

# Указываем путь к log-файлу
log="/var/log/routing.log"

# Задаем периодичность опроса шлюзов.
# 30s - 30 секунд
# 10m - 10 минут
# 1h - 1 час
check_period="30s"

# Если log-файл не найден, создаем его, иначе отчищаем
clear_log ()
{
if [ ! -f ${log} ]
then
    touch ${log}
else
    cat /dev/null > ${log}
fi
}

# Инициализируем переменные
init ()
{
    dns1="8.8.8.8"
    gw1="10.10.10.1"
    gw2="10.0.0.1"
    prefered_gw=${gw1}

    dev_if1="ens160"
    dev_if2="ens192"

    if1=`ifconfig ${dev_if1} | awk -F ' *|:' '/inet addr/{print $4}'`
    if2=`ifconfig ${dev_if2} | awk -F ' *|:' '/inet addr/{print $4}'`

# gateway as default for eth0
    /sbin/ip route add default via ${gw1} dev ${dev_if1}

# Текущие статусы шлюзов: 0 - шлюз недоступен, 1 - шлюз работает
    gw1_curr_status=0
    gw2_curr_status=0

# Текущие потери пакетов на шлюзе
    gw1_curr_packet_loss=0
    gw2_curr_packet_loss=0

# Максимальный процент потерь пакетов, при превышении данного числа, шлюз считается недоступным
    gw1_max_packet_loss=35
    gw2_max_packet_loss=40

# Отчищаем log-файл и сохраняем значения основных переменных
    clear_log
    echo `date +"%T %d.%m.%Y"`." Init environment OK. Check gateways status every ${check_period}." >> ${log}
    echo `date +"%T %d.%m.%Y"`." ISP1 [if1=${if1}, dev_if1=${dev_if1}, gw1=${gw1}], ISP2 [if2=${if2}, dev_if2=${dev_if2}, gw2=${gw2}]" >> ${log}
}

# Данная функция определяет текущее состояние каждого из шлюзов.
# Если текущий процент потерь меньше максимально допустимого, то считаем, что шлюз доступен.
get_current_status ()
{
    echo `date +"%T %d.%m.%Y"`." Get current status ISP gateways." >> ${log}

# Get current status default gateway ISP1
    gw1_curr_packet_loss=`ping -I ${dev_if1} -c20 -l20 -q -W3 ${gw1} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
    dns1_curr_packet_loss=`ping -I ${dev_if1} -c20 -l20 -q -W3 ${dns1} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
    if [ ${gw1_curr_packet_loss} -le ${gw1_max_packet_loss} -a ${dns1_curr_packet_loss} -le ${gw1_max_packet_loss} ]
    then
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - OK]. Current packet loss on ${gw1} via ${dev_if1} is ${gw1_curr_packet_loss}%." >> ${log}
        gw1_curr_status=1
    else
        echo `date +"%T %d.%m.%Y"`. "ISP1. [STATUS - CRITICAL]. Current packet loss on ${gw1} via ${dev_if1} is ${gw1_curr_packet_loss}%." >> ${log}
        gw1_curr_status=0
    fi

# Get current status default gateway ISP2
    gw2_curr_packet_loss=`ping -I ${dev_if2} -c20 -l20 -q -W3 ${gw2} | grep loss | awk '{print $(NF-4)}' | cut -d"%" -f1`
    if [ ${gw2_curr_packet_loss} -le ${gw2_max_packet_loss} ]
    then
        echo `date +"%T %d.%m.%Y"`. "ISP2. [STATUS - OK]. Current packet loss on ${gw2} via ${dev_if2} is ${gw2_curr_packet_loss}%." >> ${log}
        gw2_curr_status=1
    else
        echo `date +"%T %d.%m.%Y"`. "ISP2. [STATUS - CRITICAL]. Current packet loss on ${gw2} via ${dev_if2} is ${gw2_curr_packet_loss}%." >> ${log}
        gw2_curr_status=0
    fi
}

# Данная функция производит переключение шлюза по умолчанию в зависимости от результатов полученных в get_current_status ()
# На данный момент предпочитаемым шлюзом может быть только ${gw1}
switch_default_gw ()
{
    curr_gw=`ip route show | grep default | awk '{print $3}'`
    if [ ${curr_gw} = ${prefered_gw} -a ${gw1_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "[STATUS - OK]. Current default gateway is prefered and running up. Nothing to do." >> ${log}
        return
    fi

    if [ ${curr_gw} = ${prefered_gw} -a ${gw1_curr_status} -eq 0 -a ${gw2_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "Prefered gw ${gw1} is down. Change default gw to ${gw2}" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "ip route replace default via ${gw2} dev ${dev_if2}" >> ${log}
        /sbin/ip route replace default via ${gw2} dev ${dev_if2}
        return
    fi

    if [ ${curr_gw} != ${prefered_gw} -a ${gw1_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "Prefered gw ${prefered_gw} is running up now. Change default gw ${curr_gw} to prefered ${prefered_gw}" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "ip route replace default via ${gw1} dev ${dev_if1}" >> ${log}
        /sbin/ip route replace default via ${gw1} dev ${dev_if1}
        return
    fi

    if [ ${curr_gw} != ${prefered_gw} -a ${gw1_curr_status} -eq 0 -a ${gw2_curr_status} -eq 1 ]
    then
        echo `date +"%T %d.%m.%Y"`. "Prefered gw ${prefered_gw} is still down. Current default gw is ${gw2}" >> ${log}
        return
    fi

    if [ ${gw1_curr_status} -eq 0 -a ${gw2_curr_status} -eq 0 ]
    then
        echo "*************************************************************************" >> ${log}
        echo `date +"%T %d.%m.%Y"`. "CRITICAL. Two gateways is down. Try again later." >> ${log}
        echo "*************************************************************************" >> ${log}
        return
    fi
}

# Инициализируем переменные
init

# "Заходим" в вечный цикл, в котором по очереди вызываем функции get_current_status () и switch_default_gw ()
# После этого делаем паузу, время паузы задается в переменной ${check_period}
while [ 1 ]
do
    get_current_status
    switch_default_gw
    sleep ${check_period}
done
