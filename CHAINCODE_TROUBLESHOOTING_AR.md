# دليل استكشاف أخطاء نشر Chaincode 🔧

## الخطأ الأساسي:
```
Error: failed to read chaincode package at 'basic.tar.gz': open basic.tar.gz: no such file or directory
```

---

## 🚨 الفحوصات السريعة

### 1️⃣ التحقق من الملفات الأساسية:
```bash
cd /workspaces/fabricNew

# تحقق من وجود ملفات chaincode
ls -la chaincode-bcms/hybrid-batch/
# يجب أن يظهر:
# ✓ main.go
# ✓ smartcontract_hybrid.go
# ✓ go.mod
# ✓ go.sum
```

### 2️⃣ التحقق من حالة Docker:
```bash
# تأكد من تشغيل Docker
docker ps

# تأكد من عدم وجود حاويات معطوبة
docker container ls -a | grep -E "basic|chaincode" | awk '{print $1}' | xargs -r docker rm -f

# تنظيف الأحجام المتبقية
docker volume prune -f
```

### 3️⃣ تنظيف الشبكة السابقة:
```bash
cd /workspaces/fabricNew/test-network

# أطفئ الشبكة بالكامل
./network.sh down

# أزل الملفات المتبقية
rm -f *.tar.gz log.txt
docker-compose down -v 2>/dev/null || true
```

### 4️⃣ التحقق من متغيرات البيئة:
```bash
# افحص Go environment
go version
echo "GOFLAGS: $GOFLAGS"
echo "GOPATH: $GOPATH"
echo "GO111MODULE: $GO111MODULE"

# افحص Fabric environment
echo "FABRIC_CFG_PATH: $FABRIC_CFG_PATH"
export FABRIC_CFG_PATH=/workspaces/fabricNew/config
```

### 5️⃣ التحقق من الشبكة يدويًا:
```bash
cd /workspaces/fabricNew

# 1. بدء الشبكة
cd test-network
./network.sh up createChannel -c mychannel -ca -s couchdb

# 2. انتظر 30 ثانية
sleep 30

# 3. تحقق من الحاويات
docker ps

# 4. جرب النشر يدويًا
export GOFLAGS="-mod=mod"
export GOWORK="off"
export GO111MODULE="on"
./network.sh deployCC \
    -ccn basic \
    -ccp /workspaces/fabricNew/chaincode-bcms/hybrid-batch \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
```

---

## 🔍 استكشاف الأخطاء المتقدم

### إذا أعطاك: `cannot find module providing package`
**السبب**: انقطاع الإنترنت أو مشكلة في Download BLAKE3

**الحل**:
```bash
cd /workspaces/fabricNew/chaincode-bcms/hybrid-batch
go mod tidy
go mod download
export GOPROXY=direct
export GOSUMDB=off
```

### إذا أعطاك: `permission denied`
**السبب**: صلاحيات الملفات غير صحيحة

**الحل**:
```bash
chmod +x /workspaces/fabricNew/test-network/scripts/*.sh
chmod +x /workspaces/fabricNew/test-network/network.sh
```

### إذا أعطاك: `peer version > /dev/null 2>&1: command not found`
**السبب**: peer binary غير موجود في PATH

**الحل**:
```bash
# تحقق من وجود البيناريات
ls -la /workspaces/fabricNew/bin/

# أضف إلى PATH
export PATH=/workspaces/fabricNew/bin:$PATH
which peer
```

### إذا أعطاك: `TLS Certificate errors`
**السبب**: شهادات TLS غير صحيحة أو منتهية الصلاحية

**الحل**:
```bash
# تنظيف الشهادات والبدء من جديد
cd /workspaces/fabricNew/test-network
rm -rf organizations crypto-config
./network.sh down
./network.sh up createChannel -c mychannel -ca -s couchdb
```

---

## 🧪 اختبار النشر خطوة بخطوة

### اختبار 1: تغليف Chaincode:
```bash
cd /workspaces/fabricNew/test-network
export GOFLAGS="-mod=mod"
export GOWORK="off"

# يجب أن ينشئ: basic.tar.gz
./scripts/packageCC.sh basic /workspaces/fabricNew/chaincode-bcms/hybrid-batch go 1.0

# تحقق من النتيجة
ls -lh basic.tar.gz
```

### اختبار 2: حساب Package ID:
```bash
cd /workspaces/fabricNew/test-network

# يجب أن يحسب بدون خطأ
peer lifecycle chaincode calculatepackageid basic.tar.gz

# الناتج يجب أن يكون مشابهاً:
# basic:xyz...
```

### اختبار 3: تث بيت Chaincode:
```bash
cd /workspaces/fabricNew/test-network

# تعيين البيئة
. scripts/envVar.sh
setGlobals 1

# يجب أن ينجح
peer lifecycle chaincode install basic.tar.gz
```

### اختبار 4: الاستعلام المثبت:
```bash
cd /workspaces/fabricNew/test-network

. scripts/envVar.sh
setGlobals 1

# يجب أن يظهر basic chaincode
peer lifecycle chaincode queryinstalled
```

---

## 📋 نموذج CLI لاختبار سريع:
```bash
#!/bin/bash
set -e

ROOT=/workspaces/fabricNew
cd $ROOT/test-network

export GOFLAGS="-mod=mod"
export GOWORK="off"
export FABRIC_CFG_PATH=$ROOT/config

echo "🧹 Cleaning..."
./network.sh down || true
rm -f *.tar.gz log.txt

echo "🚀 Starting network..."
./network.sh up createChannel -c mychannel -ca -s couchdb

echo "⏳ Waiting 30 seconds for stabilization..."
sleep 30

echo "📦 Deploying chaincode..."
./network.sh deployCC \
    -ccn basic \
    -ccp "$ROOT/chaincode-bcms/hybrid-batch" \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')"

echo "✅ Deployment complete!"
```

---

## 🆘 إذا استمرت المشكلة:

1. **اجمع المعلومات**:
   ```bash
   # احفظ آخر 500 سطر من السجل
   tail -500 setup_run_*.log > /tmp/fabric_error.log
   
   # احفظ حالة Docker
   docker ps -a > /tmp/docker_status.txt
   docker logs dev-peer0.org1.example.com-basic-* > /tmp/chaincode_logs.txt 2>&1 || true
   ```

2. **ابدأ من جديد**:
   ```bash
   cd /workspaces/fabricNew
   
   # تنظيف شامل
   rm -rf test-network/organizations test-network/*.tar.gz test-network/log.txt
   docker system prune -f
   
   # تشغيل جديد
   bash setup_and_run_all.sh
   ```

3. **تحقق من السجلات**:
   ```bash
   # أحدث سجل
   ls -lt setup_run_*.log | head -1 | awk '{print $NF}' | xargs tail -200
   ```

---

## ✅ علامات النجاح:

- ❌ ❌ لا توجد أخطاء في النشر
- ✅ `Chaincode is packaged`
- ✅ `Chaincode is installed`
- ✅ `Chaincode definition is committed` 
- ✅ `InitLedger invocation success`
- ✅ `peer lifecycle chaincode queryinstalled` يظهر `basic`

---

## 📞 معلومات مفيدة:

- **المجلد الرئيسي**: `/workspaces/fabricNew`
- **مجلد Chaincode**: `/workspaces/fabricNew/chaincode-bcms/hybrid-batch`
- **مجلد Fabric**: `/workspaces/fabricNew/test-network`
- **ملف السكريبت الرئيسي**: `setup_and_run_all.sh`
- **ملف النشر**: `test-network/scripts/deployCC.sh`
- **ملف التغليف**: `test-network/scripts/packageCC.sh`

