# دليل تصحيح إعدادات Caliper

## الأخطاء المكتشفة والحلول

### 1. مشكلة Service Discovery

**الخطأ:** `discover: true` في ملف `networkConfig.yaml` يسبب فشل في العثور على خطة المصادقة (Endorsement Plan).

**الحل:** تغيير القيمة إلى `discover: false` في ملف `networkConfig.yaml`:

```yaml
connectionProfile:
  path: 'networks/connection-org1.yaml'
  discover: false  # ⚠️ يجب أن تكون false
```

### 2. مشكلة مسار المفتاح الخاص

**الخطأ:** اسم ملف المفتاح الخاص ليس ثابتاً (يحتوي على hash فريد).

**الحل:** استخدام أمر `find` للعثور على المفتاح ديناميكياً:

```bash
KEY_PATH=$(find /workspaces/fabric_certificate_MT/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore -name "*_sk" | head -n 1)
```

### 3. مشكلة وسائط العقد الذكي

**الخطأ:** دالة `CreateAsset` تتوقع 5 وسائط بالترتيب التالي:
- `id` (string)
- `color` (string)
- `size` (string/number)
- `owner` (string)
- `appraisedValue` (string/number)

**الحل:** تصحيح استدعاء الدالة في ملف `workload/issueCertificate.js`:

```javascript
contractArguments: [assetID, 'blue', '5', 'Tom', '350']
```

## خطوات التشغيل الصحيحة

### 1. تأكد من تشغيل الشبكة

```bash
cd /workspaces/fabric_certificate_MT/test-network
./network.sh up createChannel -ca
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-javascript -ccl javascript
```

### 2. تشغيل السكربت المحدّث

```bash
cd /workspaces/fabric_certificate_MT/caliper-workspace
chmod +x full_test.sh
./full_test.sh
```

## الملفات المصححة

تم إنشاء الملفات التالية مع التصحيحات:

- `networkConfig_FIXED.yaml` - ملف إعداد الشبكة الصحيح
- `connection-org1_FIXED.yaml` - ملف الاتصال الصحيح
- `package_FIXED.json` - ملف الاعتماديات المحدّث
- `full_test.sh` - السكربت المحدّث (في التقرير الرئيسي)

## ملاحظات مهمة

1. **المسارات المطلقة:** تأكد من استخدام المسارات المطلقة في بيئة Codespaces (`/workspaces/fabric_certificate_MT/...`).

2. **إصدار Fabric:** تأكد من استخدام الإصدار الصحيح عند ربط Caliper:
   ```bash
   npx caliper bind --caliper-bind-sut fabric:2.5
   ```

3. **الشهادات:** تأكد من أن الشبكة قد تم تشغيلها بنجاح وأن الشهادات موجودة في المسارات المحددة.

4. **المنافذ:** تأكد من أن المنافذ التالية متاحة:
   - `7051` - Peer0 Org1
   - `9051` - Peer0 Org2
   - `7050` - Orderer
   - `7054` - CA Org1

## استكشاف الأخطاء

إذا استمرت المشاكل، تحقق من:

1. **سجلات Docker:**
   ```bash
   docker logs peer0.org1.example.com
   docker logs orderer.example.com
   ```

2. **حالة الشبكة:**
   ```bash
   docker ps -a
   ```

3. **الشهادات:**
   ```bash
   ls -la /workspaces/fabric_certificate_MT/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore/
   ```

## المراجع

- [Hyperledger Caliper Documentation](https://hyperledger.github.io/caliper/)
- [Fabric Samples Repository](https://github.com/hyperledger/fabric-samples)
- [Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
