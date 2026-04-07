# 📋 دليل تنفيذ BCMS Benchmark — خطوات مرتبة

> **المشروع:** BCMS (Blockchain Certificate Management System)  
> **الشبكة:** Hyperledger Fabric 2.5.9  
> **أداة القياس:** Hyperledger Caliper 0.6.0  
> **آخر تشغيل ناجح:** 2026-04-07

---

## 🗂️ الملفات المستخدمة في التنفيذ

### 1️⃣ ملفات الإعداد (Setup Scripts)

| الملف | الموقع | الغرض |
|---|---|---|
| `pre-ren.sh` | `/fabricNew/pre-ren.sh` | إعداد البيئة مرة واحدة (CRLF، binaries، Caliper install) |
| `run_benchmark_only.sh` | `/fabricNew/run_benchmark_only.sh` | تشغيل الشبكة + نشر الكود + تنفيذ Benchmark |

### 2️⃣ ملفات إعداد الشبكة (Network Config)

| الملف | الموقع | الغرض |
|---|---|---|
| `networkConfig.yaml` | `caliper-workspace/networks/networkConfig.yaml` | إعداد Caliper: الهويات، المنظمات، القناة |
| `connection-org1.yaml` | `caliper-workspace/networks/connection-org1.yaml` | اتصال Caliper بـ Org1 (مع orderer) |
| `connection-org2.yaml` | `caliper-workspace/networks/connection-org2.yaml` | اتصال Caliper بـ Org2 (مع orderer) |

### 3️⃣ ملفات Benchmark

| الملف | الموقع | الغرض |
|---|---|---|
| `benchConfig.yaml` | `caliper-workspace/benchmarks/benchConfig.yaml` | تعريف الـ rounds (TPS، المدة، الدوال) |
| `issueCertificate.js` | `caliper-workspace/workload/issueCertificate.js` | workload: إصدار شهادة |
| `verifyCertificate.js` | `caliper-workspace/workload/verifyCertificate.js` | workload: التحقق من شهادة |
| `queryAllCertificates.js` | `caliper-workspace/workload/queryAllCertificates.js` | workload: استعلام كل الشهادات |
| `revokeCertificate.js` | `caliper-workspace/workload/revokeCertificate.js` | workload: إلغاء شهادة |

### 4️⃣ ملفات الشبكة (Fabric Network)

| الملف | الموقع | الغرض |
|---|---|---|
| `network.sh` | `test-network/network.sh` | إنشاء/إيقاف شبكة Fabric |
| `chaincode-go/` | `asset-transfer-basic/chaincode-go/` | كود الـ Smart Contract |
| `package.json` | `caliper-workspace/package.json` | تبعيات Caliper |

### 5️⃣ ملفات المخرجات (Output)

| الملف | الموقع | الغرض |
|---|---|---|
| `report.html` | `caliper-workspace/report.html` | تقرير Caliper التلقائي |
| `report_custom.html` | `caliper-workspace/report_custom.html` | تقرير مخصص (PhD-level) |
| `setup_*.log` | `/fabricNew/setup_*.log` | سجل تنفيذ pre-ren.sh |

---

## 🚀 خطوات التنفيذ بالترتيب

### الخطوة 0️⃣ — فتح WSL Terminal
```bash
# من Windows Terminal أو PowerShell
wsl
cd /mnt/c/Users/USERW/pro1/fabricNew
```

---

### الخطوة 1️⃣ — إعداد البيئة (مرة واحدة فقط)
> **الملف:** `pre-ren.sh`  
> يُنفَّذ **مرة واحدة** فقط عند أول تشغيل أو بعد تغيير البيئة.

```bash
chmod +x pre-ren.sh
bash pre-ren.sh
```

**ماذا يفعل:**
- ✅ تحويل CRLF → LF على جميع الملفات
- ✅ إعداد Git line endings
- ✅ تنزيل Fabric binaries (peer, configtxgen...)
- ✅ التحقق من أدوات النظام (jq, docker, curl, wget)
- ✅ إنشاء `package.json` لـ Caliper
- ✅ تثبيت Caliper 0.6.0 + Bind لـ fabric:2.5
- ✅ إنشاء connection profiles أولية

---

### الخطوة 2️⃣ — تشغيل الشبكة والـ Benchmark
> **الملف:** `run_benchmark_only.sh`  
> يُنفَّذ في **كل مرة** تريد تشغيل Benchmark جديد.

```bash
chmod +x run_benchmark_only.sh
bash run_benchmark_only.sh
```

**ماذا يفعل:**
1. 🧹 تنظيف Docker containers و images القديمة
2. 🗑️ حذف التقارير القديمة (report.html, caliper.log)
3. 🌐 تشغيل شبكة Fabric: `network.sh up createChannel -c mychannel -ca -s couchdb`
4. ⏳ انتظار 30 ثانية لاستقرار CouchDB والـ Peers
5. 📦 نشر الـ Smart Contract (chaincode basic)
6. ⏳ انتظار 15 ثانية لاستقرار الـ chaincode
7. 🔑 الكشف الديناميكي عن المفاتيح الخاصة والشهادات
8. ⚙️ إنشاء `networkConfig.yaml` بمسارات مطلقة
9. ⚙️ إنشاء `connection-org1.yaml` و `connection-org2.yaml` كاملتين
10. 🏃 تشغيل Caliper Benchmark (6 rounds)
11. 📊 التحقق من إنشاء `report.html`

---

### الخطوة 3️⃣ — إصلاح مشكلة Multiple Bindings (إذا ظهرت)
> تظهر هذه المشكلة إذا تم تشغيل `pre-ren.sh` ثم `run_benchmark_only.sh` بحيث يوجد كلا الـ fabric-network و fabric-gateway.

```bash
cd caliper-workspace
rm -rf node_modules/fabric-network node_modules/fabric-common node_modules/fabric-ca-client
```

ثم أعد تشغيل Caliper مباشرة:
```bash
npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test \
    --caliper-fabric-gateway-enabled
```

---

### الخطوة 4️⃣ — عرض التقرير
```bash
# فتح التقرير في المتصفح (Windows)
explorer.exe "C:\\Users\\USERW\\pro1\\fabricNew\\caliper-workspace\\report.html"
```

---

## 📊 النتائج المتوقعة (آخر تشغيل ناجح)

| الدالة | نجاح | فشل | TPS | متوسط الاستجابة |
|---|---|---|---|---|
| VerifyCertificate | 3000 | **0** | 100.2 | 0.02s |
| QueryAllCertificates | 1496 | **0** | 50.1 | 0.02s |
| RevokeCertificate | 1496 | **0** | 50.2 | 1.28s |
| GetCertificatesByStudent | 2248 | **0** | 75.1 | 0.02s |
| GetAuditLogs | 896 | **0** | 30.2 | 0.04s |

> **ملاحظة:** وقت التنفيذ الإجمالي ≈ **220 ثانية** (3.7 دقيقة)

---

## ⚠️ تنبيهات مهمة

> [!WARNING]
> لا تنفّذ `pre-ren.sh` و `run_benchmark_only.sh` في نفس الجلسة دون حذف `fabric-network` من `node_modules` أولاً، وإلا ستظهر مشكلة **Multiple Bindings**.

> [!NOTE]
> `run_benchmark_only.sh` يحذف تلقائياً ملفات الـ networks القديمة ويُنشئها من جديد مع المسارات الصحيحة في كل تشغيل.

> [!TIP]
> إذا فشل أي round، تحقق من:
> - `docker ps` — هل الـ containers تعمل؟
> - `caliper-workspace/caliper.log` — لمعرفة سبب الخطأ
> - مسارات الشهادات والمفاتيح في `networkConfig.yaml`

---

## 🔄 ملخص الأوامر السريعة

```bash
# ═══ المرة الأولى فقط ═══
bash pre-ren.sh

# ═══ كل تشغيل جديد ═══
bash run_benchmark_only.sh

# ═══ إصلاح Multiple Bindings ═══
cd caliper-workspace && rm -rf node_modules/fabric-network node_modules/fabric-common node_modules/fabric-ca-client && cd ..

# ═══ تشغيل Caliper مباشرة (بعد الإصلاح) ═══
cd caliper-workspace && npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled
```
