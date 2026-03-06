import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

describe('E2E: Package Verification', () => {
    // 1. Собираем проект один раз перед всеми тестами
    beforeAll(() => {
        execSync('npm run build', { cwd: resolve(import.meta.dirname, '../..') });
    });

    it('готовый пакет в dist/ должен работать корректно', async () => {
        // 2. Импортируем всё сразу
        const pkg = await import('../../dist/index.js');
        const dtsPath = resolve(import.meta.dirname, '../../dist/index.d.ts');

        // 3. Проверяем математику (это гарантирует, что функции экспортированы и работают)
        expect(pkg.sum(10, 20)).toBe(30);
        expect(pkg.subtract(20, 10)).toBe(10);
        expect(pkg.multiply(2, 3)).toBe(6);

        // 4. Проверяем наличие типов для IDE
        expect(existsSync(dtsPath)).toBe(true);
    });
});
