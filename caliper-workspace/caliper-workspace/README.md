# Hyperledger Caliper Benchmark للشبكة

هذا المجلد يحتوي على إعدادات وسكربتات Hyperledger Caliper لاختبار أداء شبكة Fabric.

## 📋 المتطلبات الأساسية

- Hyperledger Fabric v2.5 (test-network يجب أن تكون قيد التشغيل)
- Node.js v14 أو أحدث
- npm v6 أو أحدث
- العقد الذكي `basic` يجب أن يكون منشوراً على القناة `mychannel`

## 🚀 خطوات التشغيل السريع

### 1. تشغيل شبكة Fabric

```bash
cd ../test-network
./network.sh down
./network.sh up createChannel -ca
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-javascript -ccl javascript
```

### 2. تشغيل Caliper (الطريقة الآلية)

```bash
cd ../caliper-workspace
chmod +x fix_and_run_caliper.sh
./fix_and_run_caliper.sh
```

السكربت سيقوم تلقائياً بـ:
- ✅ البحث عن المفتاح الخاص ديناميكياً
- ✅ إنشاء ملفات الإعداد الصحيحة
- ✅ تثبيت الاعتماديات
- ✅ تشغيل الاختبار
- ✅ إنشاء تقرير HTML

### 3. عرض النتائج

بعد اكتمال الاختبار، افتح ملف `report.html` في المتصفح لعرض النتائج التفصيلية.

## 📁 هيكل المجلد

```
caliper-workspace/
├── benchmarks/
│   └── benchConfig.yaml          # إعدادات الاختبار (الجولات، معدل TPS)
├── networks/
│   ├── networkConfig.yaml        # يتم إنشاؤه تلقائياً
│   └── connection-org1.yaml      # يتم إنشاؤه تلقائياً
├── workload/
│   ├── issueCertificate.js       # إصدار شهادات جديدة
│   ├── verifyCertificate.js      # التحقق من الشهادات
│   ├── revokeCertificate.js      # إلغاء الشهادات
│   └── queryAllCertificates.js   # الاستعلام عن جميع الشهادات
├── fix_and_run_caliper.sh        # السكربت الآلي الشامل
├── package.json                  # اعتماديات Node.js
└── README.md                     # هذا الملف
```

## 🔧 التشغيل اليدوي (للمتقدمين)

إذا كنت تريد التحكم الكامل:

```bash
# 1. تثبيت الاعتماديات
npm install

# 2. ربط Caliper مع Fabric 2.5
npx caliper bind --caliper-bind-sut fabric:2.5

# 3. تشغيل الاختبار
npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```

## ⚠️ الأخطاء الشائعة والحلول

### خطأ: "No endorsement plan available"

**السبب:** Service Discovery مفعّل (`discover: true`)

**الحل:** تأكد من أن `discover: false` في ملف `networkConfig.yaml`

### خطأ: "Private key not found"

**السبب:** مسار المفتاح الخاص غير صحيح

**الحل:** استخدم السكربت الآلي `fix_and_run_caliper.sh` الذي يكتشف المسار تلقائياً

### خطأ: "Chaincode error: asset already exists"

**السبب:** محاولة إنشاء أصل بنفس الـ ID

**الحل:** ملفات workload تستخدم IDs عشوائية، لا حاجة لتعديل

### خطأ: "Failed to connect to peer"

**السبب:** الشبكة غير قيد التشغيل أو المنافذ مغلقة

**الحل:** 
```bash
# تحقق من حالة الشبكة
docker ps -a | grep hyperledger

# إعادة تشغيل الشبكة
cd ../test-network
./network.sh down
./network.sh up createChannel -ca
```

## 📊 فهم النتائج

التقرير الناتج (`report.html`) يحتوي على:

| المقياس | الوصف |
|---------|--------|
| **Succ** | عدد المعاملات الناجحة |
| **Fail** | عدد المعاملات الفاشلة |
| **Send Rate (TPS)** | معدل إرسال المعاملات في الثانية |
| **Throughput (TPS)** | معدل المعاملات المكتملة في الثانية |
| **Max Latency** | أقصى زمن استجابة |
| **Min Latency** | أقل زمن استجابة |
| **Avg Latency** | متوسط زمن الاستجابة |

### النتائج المتوقعة (بيئة تطوير)

- **Throughput:** 10-50 TPS
- **Avg Latency:** 0.3-1.0 ثانية
- **Success Rate:** > 95%

## 🔍 استكشاف الأخطاء المتقدم

### عرض سجلات Caliper

```bash
# تشغيل مع سجلات مفصلة
export CALIPER_LOGGING_LEVEL=debug
./fix_and_run_caliper.sh
```

### عرض سجلات Fabric

```bash
# سجلات Peer
docker logs peer0.org1.example.com

# سجلات Orderer
docker logs orderer.example.com

# سجلات Chaincode
docker logs $(docker ps -q --filter name=dev-peer)
```

### التحقق من الشهادات

```bash
# عرض الشهادات المتاحة
ls -la ../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore/

# التحقق من صلاحية الشهادة
openssl x509 -in ../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/User1@org1.example.com-cert.pem -text -noout
```

## 📚 المراجع

- [Hyperledger Caliper Documentation](https://hyperledger.github.io/caliper/)
- [Fabric Samples Repository](https://github.com/hyperledger/fabric-samples)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)

## 🤝 المساهمة

لتحسين الاختبارات أو إضافة workloads جديدة:

1. أضف ملف JavaScript جديد في `workload/`
2. قم بتحديث `benchmarks/benchConfig.yaml` لإضافة جولة جديدة
3. اختبر التعديلات محلياً
4. قم برفع التعديلات إلى المستودع

## 📝 الترخيص

Apache-2.0
