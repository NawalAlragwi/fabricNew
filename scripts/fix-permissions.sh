#!/bin/bash
set -e
# سكربت لإصلاح صلاحيات المجلدات والسكربتات
# الاستخدام: شغّل هذا الملف من جذر المستودع

echo "Fixing directory permissions (755) and making .sh files executable..."

# اجعل جميع المجلدات قابلة للدخول
find . -type d -exec chmod 755 {} +

# اجعل كل سكربت .sh قابلًا للتنفيذ
find . -type f -name "*.sh" -exec chmod 755 {} +

# اجعل Git يعلِم أن ملفات .sh قابلة للتنفيذ (يحافظ على الخاصية عند الـ commits)
git ls-files -z '*.sh' | xargs -0 -n1 git update-index --add --chmod=+x || true

echo "Permissions fixed. Review changes and commit if desired."
