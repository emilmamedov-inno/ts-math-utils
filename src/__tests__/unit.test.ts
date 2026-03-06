import { describe, it, expect } from 'vitest';
import { sum, subtract, multiply } from '../index.js';

describe('Math Utils: Unit Tests', () => {
    it('sum: должен корректно складывать любые числа', () => {
        expect(sum(2, 3)).toBe(5);
        expect(sum(-1, -2)).toBe(-3);
        expect(sum(0, 5)).toBe(5);
        expect(sum(1e6, 2e6)).toBe(3e6);
    });

    it('subtract: должен корректно вычитать любые числа', () => {
        expect(subtract(5, 3)).toBe(2);
        expect(subtract(3, 5)).toBe(-2);
        expect(subtract(5, 0)).toBe(5);
    });

    it('multiply: должен корректно умножать любые числа', () => {
        expect(multiply(3, 4)).toBe(12);
        expect(multiply(5, 0)).toBe(0);
        expect(multiply(-2, -3)).toBe(6);
        expect(multiply(2, -3)).toBe(-6);
    });
});
