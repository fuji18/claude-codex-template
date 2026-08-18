import { describe, it, expect } from 'vitest';
import { greet } from './index.js';

describe('greet', () => {
  it('名前を含む挨拶を返す', () => {
    expect(greet('Claude')).toBe('Hello, Claude!');
  });
});
