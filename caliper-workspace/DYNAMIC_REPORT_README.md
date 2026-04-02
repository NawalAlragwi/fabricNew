# تقرير BCMS BLAKE3 الديناميكي

## نظرة عامة
تم تطوير نظام ديناميكي لتوليد تقارير الأداء يعتمد على نتائج Caliper الفعلية بدلاً من البيانات الثابتة.

## كيف يعمل النظام

### 1. توليد النتائج
- `setup_and_run_all.sh` يشغل Caliper وينتج `report.html`
- `analyze_results.py` يحلل النتائج وينتج `performance_improvement.json`

### 2. التقرير الديناميكي
- `generate_dynamic_report.js` يقرأ البيانات من `performance_improvement.json`
- يقرأ إعدادات البنشمارك من `benchConfig.yaml`
- يولد `report_custom.html` بالبيانات الحديثة

### 3. الاستدعاء التلقائي
عند تشغيل `setup_and_run_all.sh`:
```bash
# بعد توليد report.html
cd caliper-workspace
node generate_dynamic_report.js
cp report_custom.html ../results/blake3/
```

## الملفات المعنية

| الملف | الوصف |
|------|-------|
| `generate_dynamic_report.js` | السكريبت الرئيسي لتوليد التقرير |
| `performance_improvement.json` | بيانات الأداء من Caliper |
| `benchConfig.yaml` | إعدادات البنشمارك |
| `report_custom.html` | التقرير المولد ديناميكياً |

## الميزات

✅ **ديناميكي**: يتغير مع كل تشغيل جديد
✅ **تلقائي**: يتم استدعاؤه من `setup_and_run_all.sh`
✅ **شامل**: يعرض جميع المقاييس والتحليلات
✅ **متجاوب**: يدعم الطباعة والتصدير لـ PDF

## التشغيل اليدوي

```bash
cd caliper-workspace
node generate_dynamic_report.js
```

## البيانات المعروضة

- TPS لكل عملية
- Latency لكل عملية
- معدل الفشل
- إجمالي المعاملات
- مقارنة مع SHA-256
- تحليل تقني لخوارزميات التجزئة
- توصيات للإنتاج

---

*تم إنشاؤه في: 2026-04-02*