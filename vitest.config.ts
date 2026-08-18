import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: [
      'src/**/*.{test,spec}.{ts,tsx}',
      'tests/**/*.{test,spec}.{ts,tsx}',
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/**',
        'dist/**',
        '.steering/**',
        '**/*.config.{ts,js}',
        '**/types/**',
      ],
      // カバレッジ閾値はテスト資産が育ってから有効化する(/harness-setup 時に検討)。
      // プロジェクト初期に有効だと /check が常に赤になるため既定では無効。
      // thresholds: {
      //   branches: 80,
      //   functions: 80,
      //   lines: 80,
      //   statements: 80,
      // },
    },
  },
});
