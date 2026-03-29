# حل مشكلة نشر Chaincode: "basic.tar.gz: no such file or directory"

## 🔴 تشخيص المشكلة الجذرية

### الأعراض:
```
Error: failed to read chaincode package at 'basic.tar.gz': open basic.tar.gz: no such file or directory
Chaincode packaging has failed
```

### السبب الرئيسي:
**الأوامر تُنفذ من مجلد الخطأ!** عندما يتم استدعاء `peer lifecycle chaincode package`، يتم البحث عن الملف المنشأ في المجلد الحالي (`test-network`)، لكن الأمر له مشاكل متعددة:

1. **مشكلة المجلد الحالي (PWD)**:
   - السكريبت `deployCC.sh` ينفذ أوامر من داخل `test-network/`
   - لكنه قد لا يرجع إلى المجلد الصحيح بعد تنفيذ الأوامر السابقة

2. **مشكلة في حساب PACKAGE_ID**:
   - السطر 89 في `packageCC.sh`:
   ```bash
   PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
   ```
   - يحاول حساب معرف الحزمة من ملف قد لا يكون موجوداً في المجلد الحالي

3. **مشكلة في المسار النسبي**:
   - عند استدعاء `network.sh` من `setup_and_run_all.sh`، قد تحدث مشاكل مع المسارات النسبية

4. **عدم التحقق من البيئة**:
   - البيئة غير معدة بشكل صحيح عندما يتم تشغيل الأوامر

---

## ✅ الحل الجذري

### الخطوة 1: تحديث ملف `packageCC.sh`

**المشكلة**: السكريبت لا يتحقق من وجود الملف المنشأ قبل محاولة حسابه.

**الحل**: إضافة تحقق من البيئة وتسجيل تفصيلي:

```bash
# بعد السطر 88 في test-network/scripts/packageCC.sh

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}

packageChaincode() {
  set -x
  
  # تحديث: تسجيل المعلومات الحالية
  infoln "Current directory: $(pwd)"
  infoln "CC_SRC_PATH: ${CC_SRC_PATH}"
  infoln "Output file: ${CC_NAME}.tar.gz"
  
  if [ ${CC_PACKAGE_ONLY} = true ] ; then
    mkdir -p packagedChaincode
    peer lifecycle chaincode package packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz \
      --path ${CC_SRC_PATH} \
      --lang ${CC_RUNTIME_LANGUAGE} \
      --label ${CC_NAME}_${CC_VERSION} >&log.txt
  else
    # تحقق من أن المسار موجود
    if [ ! -d "${CC_SRC_PATH}" ]; then
      fatalln "Chaincode source path does not exist: ${CC_SRC_PATH}"
    fi
    
    # تحقق من وجود go.mod أو package.json
    if [ "${CC_RUNTIME_LANGUAGE}" = "golang" ] && [ ! -f "${CC_SRC_PATH}/go.mod" ]; then
      fatalln "go.mod not found in ${CC_SRC_PATH}"
    fi
    
    peer lifecycle chaincode package ${CC_NAME}.tar.gz \
      --path ${CC_SRC_PATH} \
      --lang ${CC_RUNTIME_LANGUAGE} \
      --label ${CC_NAME}_${CC_VERSION} >&log.txt
  fi
  
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  
  # تحقق من أن الملف موجود بعد الإنشاء
  if [ ! -f "${CC_NAME}.tar.gz" ]; then
    fatalln "Chaincode package was not created: ${CC_NAME}.tar.gz"
  fi
  
  PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
  verifyResult $res "Chaincode packaging has failed"
  successln "Chaincode is packaged"
}
```

### الخطوة 2: تحديث ملف `deployCC.sh`

**المشكلة**: قد لا يكون في نفس المجلد عند استدعاء أوامر متعددة.

**الحل**: إضافة تسجيل وتتبع أفضل:

```bash
# في test-network/scripts/deployCC.sh بعد السطر 67

## package the chaincode
infoln "Packaging chaincode from: $CC_SRC_PATH"
./scripts/packageCC.sh $CC_NAME $CC_SRC_PATH $CC_SRC_LANGUAGE $CC_VERSION || {
  fatalln "Chaincode packaging failed"
  exit 1
}

# تحقق من وجود الملف
if [ ! -f "${CC_NAME}.tar.gz" ]; then
  fatalln "Package file not found after packaging: ${CC_NAME}.tar.gz"
  fatalln "Current directory: $(pwd)"
  fatalln "Files in current directory: $(ls -la *.tar.gz 2>/dev/null || echo 'No .tar.gz files found')"
  exit 1
fi

PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
```

### الخطوة 3: تحديث `setup_and_run_all.sh`

**المشكلة**: المسارات النسبية و GOFLAGS قد لا تُعيّن بشكل صحيح.

**الحل**: إضافة معدّلات فعّالة:

```bash
# حوالي السطر 325-350 في setup_and_run_all.sh

# تحديث: تعيين GOFLAGS قبل انتقال المجلدات
export GOFLAGS="-mod=mod"
export GOWORK="off"  # تعطيل go.work إن وجد

# انتقل إلى مجلد test-network
cd "${ROOT_DIR}/test-network"

info "Deploying BCMS Hybrid-Batch chaincode..."
infoln "Working directory: $(pwd)"
infoln "Chaincode path: ${ROOT_DIR}/chaincode-bcms/hybrid-batch"

# استخدم مسار مطلق بدلاً من نسبي
./network.sh deployCC \
    -ccn basic \
    -ccp "${ROOT_DIR}/chaincode-bcms/hybrid-batch" \
    -ccl go \
    -c mychannel \
    -ccep "OR('Org1MSP.peer','Org2MSP.peer')" \
    2>&1 | tee -a "$LOG_FILE" || {
    error "Failed to deploy hybrid chaincode"
    error "Check log at: $LOG_FILE"
    exit 1
}
```

---

## 🔧 الخطوات التطبيقية الفوراً

### 1. التحقق من البيئة:

```bash
# تحقق من وجود الملفات الأساسية
ls -la /workspaces/fabricNew/chaincode-bcms/hybrid-batch/
# يجب أن تظهر:
# - main.go ✅
# - smartcontract_hybrid.go ✅
# - go.mod ✅
# - go.sum ✅
```

### 2. تنظيف البيئة السابقة:

```bash
cd /workspaces/fabricNew
# أزل الملفات المتبقية من محاولات سابقة
find . -name "*.tar.gz" -type f -delete
find test-network -name "log.txt" -type f -delete

# أزل الشبكة والحاويات
cd test-network
./network.sh down
docker volume prune -f
```

### 3. تشغيل النشر الصحيح:

```bash
cd /workspaces/fabricNew

# مع التحقق من الخيارات
bash setup_and_run_all.sh --skip-network

# أو إذا كنت تريد كل شيء من الصفر
bash setup_and_run_all.sh
```

---

## 📋 ملخص المشاكل والحلول

| المشكلة | السبب | الحل |
|--------|------|------|
| `basic.tar.gz: no such file` | عدم وجود الملف بعد الإنشاء | إضافة تحقق بعد كل عملية إنشاء |
| أمر `calculatepackageid` يفشل | الملف غير موجود | التحقق من وجود الملف قبل حسابه |
| مسارات نسبية غير صحيحة | الانتقال بين المجلدات | استخدام مسارات مطلقة مع `${ROOT_DIR}` |
| GOFLAGS لم يُعين | go mod مشاكل في التحميل | تعيين `GOFLAGS="-mod=mod"` قبل النشر |
| env variables غير معدة | البيئة مشوشة من محاولات سابقة | تنظيف وإعادة تعريف كل variables |

---

## 🧪 اختبار الحل

بعد تطبيق الحل، قم بتشغيل:

```bash
cd /workspaces/fabricNew
bash setup_and_run_all.sh --scenario=3

# للتحقق من النجاح
docker ps                    # تحقق من الحاويات
peer chaincode query -C mychannel -n basic -c '{"function":"GetAllAssets","Args":[]}'
```

---

## 🚀 الخطوات الإضافية للوثوقية

### إنشاء سكريبت مساعد للتحقق:

```bash
#!/bin/bash
# test-network/scripts/verifyChaincode.sh

CC_NAME="${1:-basic}"
CHANNEL="${2:-mychannel}"

echo "Verifying chaincode installation..."

# 1. تحقق من الملف
if [ ! -f "${CC_NAME}.tar.gz" ]; then
    echo "❌ Package file not found: ${CC_NAME}.tar.gz"
    exit 1
fi
echo "✅ Package file exists"

# 2. تحقق من معرف الحزمة
PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
echo "✅ Package ID: $PACKAGE_ID"

# 3. تحقق من التثبيت
peer lifecycle chaincode queryinstalled
echo "✅ Chaincode is installed"
```

---

## 📞 للدعم والمساعدة الإضافية

إذا استمرت المشكلة:

1. تحقق من السجلات الكاملة:
   ```bash
   tail -200 setup_run_*.log
   ```

2. تحقق من Docker:
   ```bash
   docker logs dev-peer0.org1.example.com-basic-*
   ```

3. تحقق من البيئة:
   ```bash
   echo $GOFLAGS
   echo $GOPATH
   echo $FABRIC_CFG_PATH
   ```

