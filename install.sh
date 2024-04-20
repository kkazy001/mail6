DomainName=$1
ServerIp=$2
AccessKeyId=$3
AccessKeySecret=$4
Postmaster=$5

IFS=';' #setting comma as delimiter
read -a IpArr <<<"$ServerIp"

get_dkim() {
    chmod 777 xpath
    curl -o dkim.html "https://www.dynu.com/zh-CN/NetworkTools/DKIMWizard?SubmitButton=生成&Popup=False&DomainName=${DomainName}&Selector=default&KeySize=2048&SubmitButton=生成&X-Requested-With=XMLHttpRequest"
    rm ./${DomainName}.publickey
    rm ./${DomainName}-dkim.key
    ./xpath --file=dkim.html --path="//*[@id=\"DKIMText\"]/text()" >>./${DomainName}.publickey
    ./xpath --file=dkim.html --path="//*[@id=\"PrivateKey\"]/text()" >>./${DomainName}-dkim.key

}

aliyun_install() {
    chmod -R 777 aliyun
    sudo cp ./aliyun /usr/bin/
    aliyun configure set \
        --profile profile \
        --mode AK \
        --region ap-northeast-1 \
        --access-key-id $AccessKeyId \
        --access-key-secret $AccessKeySecret

    PublicKey=$(cat ./${DomainName}.publickey | sed ":a;N;s/\n//g;ta")
    PublicKey=${PublicKey##*-----BEGIN PUBLIC KEY-----}
    PublicKey=${PublicKey%-----END PUBLIC KEY-----}
    echo "v=DKIM1;k=rsa;p=${PublicKey}"
    aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR default._domainkey --Type TXT --Value "v=DKIM1; k=rsa; p=${PublicKey}"
    aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR @ --Type A --Value ${IpArr[0]}
    # for索引，遍历IpArr，添加A记录
    for ((i = 0; i < ${#IpArr[@]}; i++)); do
        let "j=$i+1"
        aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR mail${j} --Type A --Value ${IpArr[i]}
    done
    #aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR smtp --Type CNAME --Value ${DomainName}
    # aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR @ --Type TXT --Value "v=spf1 a mx ip4:${ServerIp}/32 ~all"

    for ((i = 0; i < ${#IpArr[@]}; i++)); do
        ipStr+="ip4:"${IpArr[i]}" "
    done
    aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR @ --Type TXT --Value "v=spf1 a mx ${ipStr} -all"
    aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR @ --Type MX --Value ${DomainName} --Priority 10
    #aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR pop3 --Type CNAME --Value ${DomainName}
    #aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR _dmarc --Type TXT --Value "v=DKIM1; k=rsa"
    aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR _dmarc --Type TXT --Value "v=DMARC1; p=quarantine; sp=r; pct=100; aspf=r; adkim=s"
    #aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR _domainkey --Type TXT --Value "o=~; r=abuse@${DomainName}"
    #aliyun alidns AddDomainRecord --DomainName ${DomainName} --RR _adsp_domainkey --Type TXT --Value "dkim=all"
}

pmta_install() {
    rpm -Uvh PowerMTA-5.0r1.rpm --nodeps --force
    sudo cp ./usr/sbin/* /usr/sbin/
    sudo cp ./license /etc/pmta
    sudo cp ./${DomainName}-dkim.key /etc/pmta

    rm ./config
    for ((i = 0; i < ${#IpArr[@]}; i++)); do
    let "j=$i+1"
        ipVStr+="<virtual-mta pmta-vmta${j}>
host-name ${DomainName}
smtp-source-host ${IpArr[i]} mail${j}.${DomainName}
domain-key default,${DomainName},/etc/pmta/${DomainName}-dkim.key

</virtual-mta>"
    done
    # sed -i "s/142.11.211.67/${ServerIp}/g" ./config


    sed "s/${DomainName}/${DomainName}/g" ./config.exp | tee config
    sed -i "s/namr/${Postmaster}/g" ./config
    sed -i "s/yuming/${DomainName}/g" ./config
    echo ${ipVStr}"
############################################################### 

<virtual-mta-pool pmta-pool-001>
virtual-mta pmta-vmta1
virtual-mta pmta-vmta2
virtual-mta pmta-vmta3
virtual-mta pmta-vmta4
virtual-mta pmta-vmta5
virtual-mta pmta-vmta6
</virtual-mta-pool>

###############################################################

<pattern-list pmta-pattern>
mail-from /@mail1.${DomainName}/ virtual-mta=pmta-vmta1
mail-from /@mail2.${DomainName}/ virtual-mta=pmta-vmta2
mail-from /@mail3.${DomainName}/ virtual-mta=pmta-vmta3
mail-from /@mail4.${DomainName}/ virtual-mta=pmta-vmta4
mail-from /@mail5.${DomainName}/ virtual-mta=pmta-vmta5
mail-from /@mail6.${DomainName}/ virtual-mta=pmta-vmta6
</pattern-list>">>./config
    sudo cp ./config /etc/pmta

    service pmta restart
    service pmtahttp restart
}

get_dkim
aliyun_install
pmta_install

echo "\"${Postmaster}@${DomainName}\",${DomainName},2525,-1,\"${Postmaster}@${DomainName}\",\"Mima123456..\",0,0,-1,0,0,0,0,0,\"\",0,"
