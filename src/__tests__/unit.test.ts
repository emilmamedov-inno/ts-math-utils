import { describe, it, expect } from 'vitest';
import { sum, subtract, multiply } from '../index.js';

describe('sum', () => {
    it('adds two positive numbers', () => {
        expect(sum(2, 3)).toBe(5);
    });

    it('adds negative numbers', () => {
        expect(sum(-1, -2)).toBe(-3);
    });

    it('adds zero', () => {
        expect(sum(0, 5)).toBe(5);
    });

    it('handles large numbers', () => {
        expect(sum(1000000, 2000000)).toBe(3000000);
    });
});

describe('subtract', () => {
    it('subtracts two numbers', () => {
        expect(subtract(5, 3)).toBe(2);
    });

    it('returns negative for smaller minus larger', () => {
        expect(subtract(3, 5)).toBe(-2);
    });

    it('subtracts zero', () => {
        expect(subtract(5, 0)).toBe(5);
    });
});

describe('multiply', () => {
    it('multiplies two positive numbers', () => {
        expect(multiply(3, 4)).toBe(12);
    });

    it('multiplies by zero', () => {
        expect(multiply(5, 0)).toBe(0);
    });

    it('multiplies negative numbers', () => {
        expect(multiply(-2, -3)).toBe(6);
    });

    it('multiplies positive and negative', () => {
        expect(multiply(2, -3)).toBe(-6);
    });
});
