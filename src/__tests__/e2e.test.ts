import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

describe('E2E: Package Integration', () => {
    beforeAll(() => {
        // Build the package before running E2E tests
        execSync('npm run build', { cwd: resolve(import.meta.dirname, '../..') });
    });

    it('should export sum function from built package', async () => {
        const pkg = await import('../../dist/index.js');
        expect(pkg.sum).toBeDefined();
        expect(typeof pkg.sum).toBe('function');
    });

    it('should export subtract function from built package', async () => {
        const pkg = await import('../../dist/index.js');
        expect(pkg.subtract).toBeDefined();
        expect(typeof pkg.subtract).toBe('function');
    });

    it('should export multiply function from built package', async () => {
        const pkg = await import('../../dist/index.js');
        expect(pkg.multiply).toBeDefined();
        expect(typeof pkg.multiply).toBe('function');
    });

    it('should produce correct results from built package', async () => {
        const pkg = await import('../../dist/index.js');
        expect(pkg.sum(10, 20)).toBe(30);
        expect(pkg.subtract(20, 10)).toBe(10);
        expect(pkg.multiply(5, 6)).toBe(30);
    });

    it('should have type declaration files', async () => {
        const { existsSync } = await import('node:fs');
        const dtsPath = resolve(import.meta.dirname, '../../dist/index.d.ts');
        expect(existsSync(dtsPath)).toBe(true);
    });
});
