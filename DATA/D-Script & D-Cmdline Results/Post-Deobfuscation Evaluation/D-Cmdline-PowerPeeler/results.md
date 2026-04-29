# API Sequence Evaluation

## Summary
- Total samples: 375
- Instruction capture eligible: 371
- instructionCount = 0: 1
- Effective action sequence empty: 62
- Instruction list non-empty but action sequence empty: 61
- Important API non-empty: 270
- Important API empty: 105
- Capability sequence non-empty: 296
- Average obfuscation score: 13.63
- Average wrapper depth: 0.04

| File | Mode | Normalize | Metrics | Source | Safety | Coverage | Instructions | Effective Actions | Effective APIs | Effective Caps | Obf | TimedOut |
|------|------|-----------|---------|--------|--------|----------|--------------|-------------------|----------------|----------------|-----|----------|
| 004fb1dc2620386d6c1a8ef970a486e9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 711 | 2 | 0 | 2 | 67 | False |
| 00d806e934eee66152b34fbbde879fa6.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 694 | 7 | 2 | 1 | 20 | False |
| 01ac59794106da1524d4d96b5aedf471.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 01c563690ffd0edafc249ecc77a1c9d8.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 48 | 1 | 0 | 0 | 6 | False |
| 02d82dda8f2750b305b9c0976d559aaf.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 5044 | 37 | 1 | 3 | 21 | False |
| 035f2018889ce0d07f9f51c796b621a8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 316 | 0 | 0 | 0 | 6 | False |
| 039e645a7b120f135829b66ab0fe1168.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 177 | 3 | 2 | 2 | 13 | False |
| 05a55983f17e35b0bd96e4c2a6e41fb1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| 06fc0104ae06c5642f01921c8f2551d4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 07902bcec912c2211d1da3e48250770f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 07f973763d6669f5c54c425281674665.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| 0853bd493a6d3ff4a703492cabe06897.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 087e9b873042f93a5b0454fb387456aa.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 97 | 2 | 2 | 1 | 30 | False |
| 0977710a63aabe53588e0d748195152c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 128 | 2 | 2 | 2 | 6 | False |
| 09c74b48746d4485773e5ad2c574b7e3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 82 | 1 | 1 | 1 | 6 | False |
| 0ae8b984348b087ff19ef9d7a0da7f48.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 452 | 2 | 0 | 0 | 6 | False |
| 0b56d5f0e8b9a40a5763a98ca487242a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 97 | 1 | 0 | 0 | 6 | False |
| 0d2f54b8a7d8f66476c340e1d0e9db40.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 0d42f972e3863579b7e433f17353f5e4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 5020 | 37 | 1 | 3 | 21 | False |
| 0dd1e531ff257340e037a25097254aef.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 335 | 4 | 2 | 2 | 13 | False |
| 0e99a36e7339652aa27d9465c8fdc3a2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| 0f087ab12f9c986e06200ed5ba9d3bb0.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 575 | 5 | 2 | 1 | 12 | False |
| 0f8ee4ab3a5017e69a41ee5be221214a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 0fa1ae49f32c68c2973a19f85668e35c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 0fc9392a25646d53386bea7ac2f367d8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 591 | 20 | 7 | 2 | 20 | False |
| 100f49226c2388dd067a9bbe7485d1fb.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 101d053b0094b3f6f20d311c00e6f09c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 10a79e9c2148f359ba6b2accdacf37ec.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 738 | 4 | 1 | 3 | 10 | False |
| 1374f077f74fda35514dd75da36130da.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| 14b7062400764200af54e9f3506cc1d8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 419 | 0 | 0 | 0 | 6 | False |
| 14e9328700435020210da81037259798.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 100 | 0 | 0 | 0 | 6 | False |
| 157d0d31e7dfe854160148284b5298d8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 68 | 0 | 0 | 7 | 13 | False |
| 16632285ebcc1d28c4b6f9c8eb94621e.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 16912bab54f0bdb722f243096b9990f1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 16fbb95d35e405bfdb2551c3778a549e.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | partial_visibility | fallback_appended | 538 | 4 | 1 | 1 | 24 | False |
| 175ee32d042c2f1e958100d13442410b.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 253 | 16 | 0 | 0 | 6 | False |
| 17cdd05fa8763b7869ec594ce80e8df9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 18a95acf9cb471c3d24cabdf50d3f2b7.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 289 | 4 | 2 | 2 | 13 | False |
| 190349afef1c584473717f402fc099ec.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| 1bf71e4576dde0f8e2c8c07cc7049af3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 568 | 4 | 2 | 4 | 10 | False |
| 1c0d56a9f235820339b20b5fead169b2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 1c21f2ea07bce442f55a84999687bb96.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 1dc520a66d4b83b02d1abc207e8e23f5.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 1dee780fb11e5dfdaacd3f0c5c908c4f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 21081c6ff43ae43c08f750ea20280713.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 143 | 1 | 1 | 1 | 12 | False |
| 214e58b2ca107d11c6c0d6b7a28312ab.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 513 | 0 | 0 | 1 | 13 | False |
| 2181d9c83a4095edd990d90031ae94d9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 21c4cc550f1c97569a2e102fd691ea0c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 21eec2ded28ca4bcb10672765a1fdc97.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 2227628d221a7e164745308640c3ec65.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 22fccd4cfaa3bee27b30f7e816734b53.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 171 | 2 | 0 | 1 | 13 | False |
| 235fe01a3a61b7c3d2f816a343c82aed.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| 2387aa05b84b680bb51b0cfb3d60f05b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 23edc89712effcd118c2271f730d6a51.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 243b887d1cc72ba0789483d2616d2b5b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 259156a81c4bd8f5ca3404b2fef02c3e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 268 | 4 | 2 | 2 | 25 | False |
| 271a4e46b2ac491dd0e938c627742419.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 134 | 1 | 0 | 0 | 6 | False |
| 274b8493cb6ff94bb0aad1c8d833ef2e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 403 | 4 | 3 | 1 | 45 | False |
| 2785abefe93fd6a969d5f5a2f7e283c2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 2892b81283ad9c0e8c7be7e0626dc89a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 1186 | 2 | 0 | 0 | 6 | False |
| 2ab55433c4beddae5a3bc9c2a639d7d2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 2c05d9da78f73acf70b71e0cff5abdb3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 190 | 3 | 1 | 1 | 6 | False |
| 2c2416675787624bd0fe0fc4a5e2a816.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 79 | 1 | 1 | 2 | 13 | False |
| 2ca9023a22c16cca9527d65162134b6c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 2ccfc40d9538ce0e41932ebbab56f54e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 2f15e4b4a1af8c336cb8f6bc7d4d3077.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 2fc6ce741696928e30e67dbd23f6240a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 209 | 4 | 2 | 2 | 13 | False |
| 3019afd2094c2946a2636dbe75f6cd2d.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 97 | 2 | 2 | 1 | 30 | False |
| 30221edb3cbc493c7d078375fffbd7cf.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 3036630fb4014935c76533ed8db146d1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 127 | 2 | 1 | 2 | 6 | False |
| 329508bde7e5b6490df8ec8b2ea91a77.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| 333e3ce4c9ba2cc4ce4becbaa1a775ad.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 45 | 0 | 0 | 0 | 6 | False |
| 337690d835c5e507923566e9fa094048.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 2872 | 30 | 10 | 2 | 20 | False |
| 34349a4a4183e369d2901d5230f1a6df.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 576 | 8 | 4 | 2 | 13 | False |
| 349df1e56670ca1c70727509b4ff427b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 106 | 0 | 0 | 0 | 6 | False |
| 34bc10427e137ff53eb1037b68325692.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 606 | 6 | 2 | 1 | 6 | False |
| 3515de123d6bf762d48081ca1f51596f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 359e2f26732dc4c4917f83e51ab0b1ee.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 149 | 2 | 1 | 2 | 6 | False |
| 35a4cce89bcb813386f34fbe13f4880e.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 366b20291453e71d5d56fe08ef012fd2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 960 | 23 | 21 | 1 | 7 | False |
| 37f7457b33eda31dd5b7ae5be68ad257.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 159 | 3 | 1 | 0 | 6 | False |
| 38b0f77fb7d2b0718acd7a992d5a0cb2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 60 | 0 | 0 | 1 | 6 | False |
| 38f98275bfb42bc138ba17b73dbcc44e.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 382 | 3 | 1 | 1 | 6 | False |
| 3949847e35dfe1af9bb4529ee9c53a33.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 68 | 1 | 1 | 1 | 6 | False |
| 398df4dad14d5ec830c7c4e645610375.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 601 | 2 | 0 | 1 | 21 | False |
| 3c13c79a62e711811951965f4cfb3369.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 3c4e8a00fcaae5015bc5fa1ce10ad263.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 2083 | 1 | 0 | 1 | 6 | False |
| 3cc6cc1354c3c2d01cb6e638c671e802.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 222 | 4 | 2 | 2 | 6 | False |
| 3d0d3d8ab486f5312a44947127630a7e.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 3d5b6c3a3af088572fbbc6b77cbc4739.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 343 | 5 | 1 | 1 | 6 | False |
| 3e18ae0aefce94e69f19b16a27013df5.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 744 | 5 | 2 | 2 | 13 | False |
| 3e9b4f55134a50bd08ea14a7a057fc93.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 3f87dd4d67fbc3d426dc3f6530c235f9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 209 | 5 | 4 | 1 | 6 | False |
| 3fad375a96cce6f59eba61772e40ac3a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 367 | 4 | 2 | 2 | 13 | False |
| 3fb6ef148a07919012bebf7bebfabe7e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 3fef5d49e63459083e427835e2de9311.deob.ps1 | deob->script | direct/0 | True | instruction_list | unsafe_timeout | fallback_appended | 555 | 2 | 1 | 1 | 13 | True |
| 40a29f7aab0b55f7bc2ea51d2b15eb36.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 363 | 4 | 1 | 1 | 6 | False |
| 41534a52301d781428bd68fc7d1760d9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 43d307b43168d347745ecf8578e8aeea.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 43df228efe5bdb252f1e808dc3e355cd.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 94 | 0 | 0 | 0 | 6 | False |
| 44d9357676b23948a73741a5250f2d91.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 495e15b91a46fc465cedb59fe1f30a50.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 188 | 3 | 0 | 1 | 13 | False |
| 49a6ee5be6759b4fc872dc9da9bf4cb6.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| 4a41b0d892f08b16aa5e68ee9541abb4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 4a6a9e9fa95c601745cb33f06f7bf97a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 7730 | 37 | 3 | 2 | 6 | False |
| 4aa2395748255f7d3549e27c60d15531.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 4b280b5dc3efd82cd4538ec8f5638784.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 297 | 0 | 0 | 0 | 6 | False |
| 4c3847ceeb3c5cdde9bf7795bf0aeebe.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 7930 | 42 | 3 | 1 | 6 | False |
| 4c89b4cce0c93e2d6edc6ec818b39e0f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 88 | 1 | 1 | 0 | 26 | False |
| 4cfc245d0028828c0dba7b4c92c97f95.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 123 | 2 | 1 | 1 | 6 | False |
| 4ee32284e4d2b7accfaf28637d569bb3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 98 | 0 | 0 | 0 | 6 | False |
| 4f410632f9ac4ee0c95be952eb405ccc.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 90 | 2 | 1 | 0 | 20 | False |
| 507cb233e9bfd88c38e15fd313c078b2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 88 | 1 | 1 | 0 | 26 | False |
| 50b73b5edf92deb4d362881b87479230.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 51df1aec7cf187cd7fb8e85c23555736.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 12 | False |
| 52ecbc7debdf6661120f4f2949a15555.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 52 | 1 | 0 | 0 | 6 | False |
| 533115594ff41dc04da443ab5151a36c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 541d593daa1a55ba2fa992015f5cfb2e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 1004 | 6 | 1 | 1 | 9 | False |
| 544e9826b126f2ed3cc3e9a7e51ab6c7.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 544fc0c97554e9614f6b0af7b9808193.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 352 | 4 | 2 | 2 | 13 | False |
| 550cbb84f6a7778376b5c02d10728808.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | partial_visibility | fallback_appended | 538 | 4 | 1 | 1 | 24 | False |
| 55537e6f59bdd0a8e6e4723447ea23a7.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 56072be0f4fd650eee04a355a5db0ce4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 56ae1c5dc8995dde50f383aad88beaf4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 5785060a024a0179d716c70a02f53ed3.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 58c4c50ec5676c00080433ac11a6d751.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 225 | 1 | 0 | 0 | 18 | False |
| 59bc28b51eb85d5f3386029738fcab1a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 1015 | 6 | 1 | 1 | 9 | False |
| 5aeaaadbe1245ce0c7a4b9a1a03f9ef8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 5b23ae8f2ac54b84acb636db80bd08e5.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 91 | 0 | 0 | 1 | 6 | False |
| 5b38e93016b2f9121f6396bed8a98709.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| 5bf449b90106a647fca2589233802685.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 5c6170ea7dc56da3e8c260a5a9498aef.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 5d4bda6c8715fda47638f7853116e216.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 97 | 0 | 0 | 0 | 6 | False |
| 5e1640f4553607d0db72df448082c6be.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 257 | 5 | 3 | 3 | 13 | False |
| 5e44430badfec1630be970d9be0ac9a2.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 455 | 6 | 3 | 3 | 31 | False |
| 5eab0a90b7257e43d19dc2047ffa3dd3.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 5eb8378f1430c5d6d2ca95ac4511a5a5.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 5ee0c582f7b50fe00abf8120f65d2f97.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 0 | 24 | False |
| 5f1d010a5d3761962827f0853c1b0556.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 31 | False |
| 5f359bb2d594e3e2af1518baf878ce69.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 97 | 2 | 2 | 1 | 24 | False |
| 5f8df5306a0b2f37aef04bc3f5f632a0.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 299 | 6 | 6 | 1 | 6 | False |
| 5fd72c60eb560c4b12d7ca7acf957e6f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 600b1ef719a47218ad3535ba1a69164b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 127 | 2 | 1 | 2 | 6 | False |
| 60882b06ae402e0d7abaf55f3833bc88.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 6108a251a3dbf42895fd43f97ffa1ed8.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 6115ddaa991c5003cf9e531d4f4df4a4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 620401c4a2095ffaa9a2dbd28ba8d336.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 149 | 2 | 1 | 2 | 6 | False |
| 62707d7de7c6334d868870250caf7b6a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 75 | 0 | 0 | 1 | 13 | False |
| 628674ba534d460dc8a551793b07b3ae.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 61 | 2 | 2 | 2 | 13 | False |
| 62a8526fa690ba079aa3a576ceaa0aaa.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe | complete | 48 | 0 | 0 | 0 | 30 | False |
| 630a9b69e8d9ccabb97458b7fd5ae240.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 65710935c120cedfe7000fe30a67f25b.deob.ps1 | deob->script | direct/0 | True | instruction_list | unsafe_timeout | complete | 283 | 0 | 0 | 1 | 13 | True |
| 66d5c711c21a67f371b8bf95450c4cd9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 52 | 1 | 0 | 0 | 6 | False |
| 67165204eb3d337617dbf08864794d25.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 672aa0532feb4e41abed3298d60992d9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 6819bfc4148a6889117e1b289d4faecb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 6823d4bfa6b3fc9a8b3c73fa64be83cb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| 698486761f25eff27d2c79228ffba849.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 99 | 0 | 0 | 0 | 6 | False |
| 69dda0da45e59dd82a442e9792474bef.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 80 | 1 | 1 | 0 | 26 | False |
| 6a3e52e4fcb6c7ac808c0d60f9589f45.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 561 | 2 | 1 | 0 | 6 | False |
| 6a4d5aeed959e706e0e574f15af38ddf.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 6b7613e0a23f20ac9bff857d82eb30ca.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 106 | 0 | 0 | 0 | 6 | False |
| 6babe7699c77a5ad2f760298d6a6d6e4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 6c1b81c456dc07a65649a36b49192ea3.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 48 | 1 | 0 | 0 | 6 | False |
| 6c8ca9ff64a7e860a46677fd5ee4d131.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 211 | 3 | 2 | 2 | 13 | False |
| 6d51fc16070695efab72668bd89e53dc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 6da1d82f855d65bff5a2ee562f05bf77.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 52 | 1 | 0 | 0 | 6 | False |
| 6dbcba4a0b898ea3bada0a51a9d006d3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 105 | 0 | 0 | 0 | 6 | False |
| 6f96dbb43e57620a358f109a8cf80b09.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 6fb403d6d4e1cca7e9fe9290aead8182.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 6fc21a98eb1fc1c84bd9f5d242f3e5b1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 88 | 1 | 1 | 0 | 26 | False |
| 7099b989ea0b1145d948df0af302d0f1.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 151 | 3 | 2 | 1 | 13 | False |
| 715bf6ab17e94ce1958ff6dfb1e51e34.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 212 | 4 | 3 | 2 | 13 | False |
| 71818433d21020118113f578264fdc8f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 7298b92a63a0b823704ed5b40c2aed1a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 127 | 2 | 1 | 2 | 6 | False |
| 733ec5d2a93d0baec8f020cbe736e43d.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 694 | 7 | 2 | 1 | 20 | False |
| 736c75b2cba6d98313c66baefb4c47c4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 105 | 0 | 0 | 0 | 6 | False |
| 749356832d0173e14456f5b682f2d8c4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 766699e949bb7854f18df4e148681a9c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 770cd9273a327294dff72e3f48b1663a.deob.ps1 | deob->deob | failed/0 | True | instruction_list | unsafe_normalize_failed | complete | 0 | 0 | 0 | 1 | 19 | False |
| 7738b915274555e3376b2f4d76b867b2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 1305 | 5 | 0 | 1 | 25 | False |
| 77991a0305285339ea879fba06ef6c31.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 85 | 0 | 0 | 0 | 6 | False |
| 77cc7a93ae99a35642722535180bfc0e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 121 | 3 | 2 | 2 | 6 | False |
| 782757cc796e7130ed8800270b70a762.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 229 | 4 | 3 | 2 | 13 | False |
| 7898e37b0411dbd23b3d47803fcb5f24.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| 78d9aad3e3f246801b50fb476bb6f3c4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 618 | 5 | 0 | 0 | 19 | False |
| 7997f5928ea7b2af3aba81a59468acc9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 246 | 3 | 3 | 2 | 6 | False |
| 7a164356298bd998a290d09c7ae87ca1.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 7b2a36da1c9118654333ac64e9ad7f00.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 52 | 1 | 0 | 0 | 6 | False |
| 7d2ee7bb33d2f59951af5ff8f6a0b0b8.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 7e44b4fdfc68b980ebc21322f3caffd4.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 24 | False |
| 7ea6a2c309f48d64282b6249a12a55fc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 2578 | 16 | 0 | 0 | 6 | False |
| 7fa788e0bf8b833c7d7bc527dd502bf4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 80d01e9b23df3e6dab6ed739549dcbda.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 1242 | 64 | 0 | 1 | 6 | False |
| 81674dfe472e1b71fea0115ae14c4163.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 80 | 1 | 1 | 0 | 26 | False |
| 8240dc8d2ea512f1ea7756688a57f513.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 8283e2cb7e47379bf537bc26e963d22b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 60 | 0 | 0 | 1 | 6 | False |
| 83856cbb80780fe9b47b45d1de7223ed.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 381 | 7 | 3 | 2 | 13 | False |
| 839c25c58e991207d5b75a67fa2329fb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 317 | 7 | 3 | 2 | 13 | False |
| 8409ed15a9e5635793887cd48414db7b.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 858c6f298cffbdafe92803ba6566dfa9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| 863fd0d0543b6556a236f765d3d94ea2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| 86645790fe4551c096985cab22d439dc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 871a7f2b54db8ec6b7f7ccf770cbed5e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 5020 | 37 | 1 | 3 | 21 | False |
| 88294dd18a008617f5aa4223f8ff0847.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| 885ba03a51de2c40e7508553b87b71dc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 8b818bb41e01004eb523f44de6704c5a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 122 | 2 | 0 | 0 | 6 | False |
| 8ca6c00422a0f18945525c93bd338b05.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 211 | 3 | 2 | 2 | 13 | False |
| 8cecd953ff5ee676117e418b5919bff1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 5044 | 37 | 1 | 3 | 21 | False |
| 8d9af2feb075d4d4ee33e30b762fd653.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 98 | 0 | 0 | 0 | 6 | False |
| 8e49c5f522b5b8625b8bb9905063f166.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 5020 | 37 | 1 | 3 | 21 | False |
| 8eefaf7d971924108a69689b962d4743.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| 8f6ced885ecb3ae5a0946d264b178dc9.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 378 | 1 | 0 | 0 | 6 | False |
| 912e76f8e61afd80f52436f96640134a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 141 | 1 | 1 | 2 | 26 | False |
| 9211de2ffb95441dfcca39296eec1e68.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 81 | 0 | 0 | 1 | 6 | False |
| 92fca8f6fa0845090ff2f2040787b45b.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 122 | 2 | 0 | 0 | 6 | False |
| 937f7b52c376da87bb66d46ccadde441.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 95584abd5fead38cc2139bf4b399015d.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 80 | 1 | 0 | 0 | 6 | False |
| 9565655ae773c13eb67d8c889f7aca65.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 163 | 1 | 1 | 4 | 38 | False |
| 95e28031b0e2f72d05615450ad3a6331.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 291 | 4 | 1 | 2 | 13 | False |
| 95f2745b88bf871f68d7385321a24b4c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 364 | 4 | 2 | 2 | 13 | False |
| 96479c119cb5503532f290be4f81e7ec.deob.ps1 | deob->script | direct/0 | True | instruction_list | unsafe_timeout | complete_with_stubbed | 2229 | 8 | 1 | 1 | 12 | True |
| 968844ee13a010cb396dc616b9a0217d.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 75 | 0 | 0 | 1 | 13 | False |
| 96ad7508302206d37e6416afe87f6224.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 97679d870dc2c0eceaa496ba811aae91.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 68 | 1 | 1 | 1 | 6 | False |
| 97f39a6a00db23143187dad1c4c2f3b9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 98afdb116f852d7cb718951216286576.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 98c6d5ff7603142f49eac4306c82ddaa.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| 99b7611e5179aaa94c7c2a1f8e67e4f4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| 9a3881d00a75a519099a41def89cbf0f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 9b1334943da5c4b19b72ce3297111926.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 0 | 6 | False |
| 9b90ad866bfea7a40b481bb37a9ca634.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 106 | 1 | 1 | 1 | 11 | False |
| 9c475f377ae2a2614b6fde16d3a81c24.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 9cbc0386e7d540b0c186ee6a8cb38e99.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 9d7f826626b6618e85c59a4f9faeb758.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| 9efd67c201e3da4e25d2261040d12836.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| 9f3f1491fcff92ab986b1c9781dfe69b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 207 | 3 | 2 | 2 | 13 | False |
| a0008befc45056eb88401933e6e61b43.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| a09b94e47807b124accbea3b222cf461.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| a151ff1ba061c0afb0e5dc4399313b87.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 264 | 0 | 0 | 0 | 6 | False |
| a23c97721b9cd2d427f7af9bbdcd3f55.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 97 | 0 | 0 | 0 | 6 | False |
| a486af36de69b516792c906356f5f7ca.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 66 | 1 | 1 | 0 | 6 | False |
| a4bac9206b52caec6f0c709a1ab3344f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 156 | 4 | 3 | 1 | 18 | False |
| a547fd012e2b08854b7e5a8d0cce89e0.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 151 | 3 | 2 | 1 | 13 | False |
| a6d1cfeaf74b715130806c390a60815b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 591 | 20 | 7 | 2 | 20 | False |
| a7587481a4123b7ef8e29fb18f74cf7f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| a79c8efacb3f9bd0ca472c5a19497f5e.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 474 | 2 | 0 | 0 | 6 | False |
| ac02aa6d569ec5f77215d73b77af7c6c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| ad4126ed706cd86b549584790bfe0816.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| af1fc3379bf48f82a181de007c471cb1.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| b0540663400ddc6faf3cbb4e2f3ee68c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| b06082bb9568be7e18d648413a78b8fe.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| b06f0f5830c7479fa6f1c43b99870684.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 910 | 8 | 2 | 2 | 13 | False |
| b074e7396747a54b4b328f3b5848b48b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 504 | 3 | 2 | 4 | 10 | False |
| b1b23ac6f394c3d8c4a862d4b7d69683.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| b220ed3ba7ced6685be21073fb86173a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 186 | 1 | 1 | 1 | 13 | False |
| b30ef9b708eb98835b5b1b88f199e8b9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| b3162d06d2708e9ba08c7a36038b92ef.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| b32b7e12e23aa6deb79b02009cbeccec.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 196 | 5 | 5 | 0 | 6 | False |
| b32e3cc0119189882cef77fc2a2f7fe5.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 145 | 2 | 1 | 2 | 6 | False |
| b41a8317d5d567d9b21af614941f343f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| b4af8212a2b2472c7e7493ebcd3be4a7.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| b4d582c00a864db0825cdf3ee686d066.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 257 | 5 | 3 | 3 | 13 | False |
| b4f4da39c23a12554c28ee15548352dd.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| b5078c61c3dfe0b539802cffd1269ceb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| b5e619ae93337eaa9de47ac70988c0df.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 131 | 2 | 2 | 1 | 12 | False |
| b6f63535b0bee1f3993dc298b17fadae.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| b7f62a1adcb29f97bb1b9f51627236a0.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 564 | 6 | 1 | 1 | 20 | False |
| b8463efb009b8f6e408e7c68e6716b48.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 569 | 6 | 1 | 1 | 20 | False |
| b921a84d3586bd3d8dc5d9aefac9ad51.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 613 | 6 | 2 | 2 | 6 | False |
| b97ece05fb515b11fc18878197b368c2.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 894 | 3 | 2 | 0 | 6 | False |
| ba7d467998b22db262572ec4097e79e4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| bb408f6288017b9bfd314ec515fc7cc3.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| bbe133be6edd21cb8adcc405f8633221.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| bc37b763a94860e6ce3eee04a1742abc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 2748 | 22 | 1 | 0 | 7 | False |
| bd22796110c645b468d932732222d8c7.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 561 | 2 | 1 | 0 | 6 | False |
| be9ab8e5f3896a8d43f9cf4d3f8256c3.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 97 | 2 | 2 | 1 | 24 | False |
| bffe02a3de2e218f03d2fe68541543a4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 316 | 0 | 0 | 0 | 6 | False |
| c0307f2ccf20b1642a702bdc26364d6f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| c09220e548a82a0ef46ad3c26d3a6834.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 24 | False |
| c1eb8943ba640dfc83f0b5b81f0fd2fa.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| c39ae16132530a3c5ae2b19ffb05a3b5.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| c42ff572fbe718aa226dd5a9fbc373f1.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 135 | 2 | 1 | 2 | 6 | False |
| c45866f23ea48e53853e2fd45813a2af.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 98 | 0 | 0 | 0 | 6 | False |
| c50ff82b28ff5bced2351de3d256cf55.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 151 | 3 | 2 | 1 | 13 | False |
| c615fd8f86d2699e24ca07d86252dd86.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| c6c225d33ea8f6c051f06d2a21c630fb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| c792550ae437d915cbbad08bf565fa57.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| c7deca08f19a9e38448d587361444bc9.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 291 | 4 | 1 | 2 | 13 | False |
| c90402515922854c533f101126f1da06.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| ca7725223ab9169a00c62ce49edf0f66.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 94 | 1 | 1 | 1 | 6 | False |
| cb07de1a13d05405c2be4252f986d778.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| cb7a17827862d8f04eb89d6328d10e12.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| cc2cc10f778ed60d8c086f8b34136b75.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| ccbe24fe55c81109337d28f3dbcb8a3f.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 449 | 3 | 0 | 0 | 6 | False |
| cdc3a96e5521387dd62f7f7eb2bf0363.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| cdf1d542d5cf4ef33d38419387b3a5d7.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| cf7591b2286774987359fe2813eb0461.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 97 | 0 | 0 | 0 | 6 | False |
| cfa7b1d9b061d225271645bfdc34ed6d.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 97 | 2 | 2 | 1 | 30 | False |
| d0a3d42ff36aa154e25a6e0d8890811c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| d176f6015a0b9ff678884b0195733cd5.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| d1fb0d9e98191670b0532ca4d5ad9840.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 63 | 0 | 0 | 1 | 6 | False |
| d207c96cff31437d5d09bca3386638bc.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 360 | 0 | 0 | 0 | 6 | False |
| d2b588c682a771d3a2400ba1729ea4fc.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 143 | 1 | 1 | 1 | 12 | False |
| d605f7d5392916b976a1f21d38b5b7d1.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| d651c3873db72184fe26ad13fc387e34.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 60 | 0 | 0 | 1 | 6 | False |
| d65a18cfc601801759711997aac3e3eb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| d7bb587c84a90377cd3b3ba377bc449d.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 2578 | 16 | 0 | 0 | 6 | False |
| d970cf93f2056f06a04f9397ec1f8890.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| dbb8d164ce59c24ee3ee399ccec72126.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 278 | 1 | 0 | 0 | 6 | False |
| dbd6708dc8b3b53d5411dcf1994be5e7.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 52 | 1 | 0 | 0 | 6 | False |
| dc0add8d29c903d17f0865f7a3a79bd7.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| dc4f3137206dfc060b5cfcc85445550c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| dca097f80938d4d637cb7d01d029728c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| dcbdefa775abbbdd33733c6d76802ce4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| dda0e3a8071821b25e8aea1e5152adcb.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| ddcd791ca5d89fa268de4b5aa7d6413d.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| de8783bb90206e4970c84fabefe7ee20.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| df49e67248e76a91ca6abd8ef0d83580.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| df4de0bd80df13610b8807017f07fc16.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 80 | 1 | 1 | 0 | 26 | False |
| df4fba0a3470a24654c881c054fc88d4.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 695 | 5 | 2 | 1 | 13 | False |
| dfbc377ba8520f5b7c9823c01d629591.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 94 | 0 | 0 | 0 | 6 | False |
| dfd50e33b04699595839d798305ce865.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| e12e0de31dbb7cda0abfcf7628edb7bc.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| e2633ef500978fa3d6cd25f22df55e3a.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 695 | 5 | 2 | 1 | 13 | False |
| e2a7a6c9305c295aeddaa5a2e4a890bf.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| e30f4e4cf9b58365adfce94a561f9c2f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| e396d39daec048518ef963819552b47b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 55 | 0 | 0 | 0 | 6 | False |
| e3a4e69a135af5549e99b87186bd8a58.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 379 | 4 | 2 | 2 | 13 | False |
| e419d271fb78366b49d5de6edc9a9843.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| e52757a7fac119c994ef03f570962e3c.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 68 | 1 | 1 | 1 | 6 | False |
| e6401857515ecfaa34ba6ceecf35b0c1.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| e7961249fe86dc9a3710368f11004945.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 352 | 4 | 2 | 2 | 13 | False |
| e7ca0fe5e92bd88cfd657a040ae66e19.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 303 | 2 | 1 | 1 | 13 | False |
| ea3388ea5b8be72f31af188419431283.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | partial_visibility | complete | 48 | 1 | 0 | 0 | 24 | False |
| ea694e5107d096a6637712a86b95eb29.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 189 | 2 | 2 | 2 | 20 | False |
| ea75a9645de0ec5bcb3f5ee606c6a630.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| ea801ce81deff489f210bbae04d491a0.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| ec9bbf983f5e580306627a73fa4ca5dc.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 1 | 6 | False |
| ed2be61dccda589647a7b567f727b89c.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 367 | 4 | 2 | 2 | 13 | False |
| edb298257c5acc2b7cafee87001959e3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 104 | 1 | 1 | 2 | 13 | False |
| eddf3f7f8943e68ecbbdc51b63561802.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| ee722053a0cce8a5c548413b732b8031.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 56 | 0 | 0 | 1 | 6 | False |
| eea72bf060a1f00bcdf160bb786a46c7.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| eeb8d3f6a9ba28b17a4b0fd94a2ae9f5.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| ef133833b1d819db7d39f40c6bd10f79.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 94 | 0 | 0 | 0 | 6 | False |
| f056abc4ecaa5b3ca518e3ef5a749cbb.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| f08b6e043044a4207916f4021c4f7341.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| f17845b06c4ff2894ec646fdea840759.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| f1f87735d9bce2dcf649c44548ec14a2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| f2b2675d5ce6602a355ba366497f9c3e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 84 | 1 | 1 | 0 | 26 | False |
| f37a3633454cfa1715ef40fab87ec9e4.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| f4e4cb4dd8add96c5401ba1bf618553a.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 132 | 5 | 3 | 2 | 12 | False |
| f5b266a09b29fd97afd42466eb8f2714.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| f66741f557a8c4a2dbbd87fcb5fa3850.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 289 | 4 | 2 | 2 | 13 | False |
| f7f99b2f0e81bd0e4b5590be88695094.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| f8113723ca8d939e2744fed13ee1fd74.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | complete | 249 | 2 | 0 | 3 | 25 | False |
| f89345c79768727117b14025465f895e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| f9389296d3f83544b32fad1074800ec6.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 207 | 3 | 2 | 2 | 31 | False |
| f94b1f0ce04e952c2cce67a0d7acbff3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 127 | 2 | 1 | 2 | 6 | False |
| f96cc10151e748adae68c01a5545d241.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 280 | 1 | 1 | 0 | 6 | False |
| f9d70e60ab6650e11cee483f20c1256e.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 52 | 0 | 0 | 0 | 6 | False |
| fa09d276d7cb3ad7e7b92ea0d387aeec.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 52 | 1 | 1 | 1 | 6 | False |
| fa2cfcf8587baf6879275d49e3d8d4a3.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 105 | 0 | 0 | 0 | 6 | False |
| facee15250a6009e8999202f7ec3b5b6.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe | complete | 355 | 0 | 0 | 0 | 6 | False |
| fb1fd20a23a3e1dadca31db555b8659f.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 264 | 2 | 1 | 2 | 33 | False |
| fb34d918be5f9a6baf121e71276fe133.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 1122 | 11 | 5 | 2 | 13 | False |
| fb43ea588dc80e46628182fe3b6eca9b.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 588 | 12 | 6 | 2 | 13 | False |
| fc6ed4fbace0a892fb6617431f52d8da.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 150 | 3 | 2 | 2 | 13 | False |
| fcf9feb43e98d665edc09316d1edf4c2.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 694 | 7 | 2 | 1 | 20 | False |
| fd6c1f822147f198f47d9c29259405d7.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 64 | 1 | 1 | 1 | 6 | False |
| fde2cac273c95159ebfc4c0c2253e513.deob.ps1 | deob->script | unwrapped_wrapper/1 | True | instruction_list | partial_visibility | complete | 48 | 1 | 0 | 0 | 24 | False |
| fe928f1521c1f0fb686224bdb6b010c8.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 291 | 4 | 1 | 2 | 13 | False |
| ff35237a4bbb510d6f6dd4c365fe1690.deob.ps1 | deob->script | direct/0 | True | instruction_list | partial_visibility | fallback_appended | 695 | 5 | 2 | 1 | 13 | False |
| ffbbaabadaf6c225157f0ba99063acfa.deob.ps1 | deob->script | direct/0 | True | instruction_list | safe_with_stubbed | complete_with_stubbed | 218 | 4 | 2 | 2 | 27 | False |

## 004fb1dc2620386d6c1a8ef970a486e9.deob.ps1
SampleId: `004fb1dc2620386d6c1a8ef970a486e9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`711`  eligible=`True`  noise=`709`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`10`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`911`  byteArrays=`0`  astNodes=`587`  obf=`67`  clarity=`33`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- set-alias
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 00d806e934eee66152b34fbbde879fa6.deob.ps1
SampleId: `00d806e934eee66152b34fbbde879fa6`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`694`  eligible=`True`  noise=`687`
Actions: normalized=`7`  effective=`7`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`264`  byteArrays=`0`  astNodes=`64`  obf=`20`  clarity=`80`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- start-bitstransfer
- get-content
- powershell.exe
Recorded important API sequence:
- add-type
- powershell.exe
Effective important API sequence:
- add-type
- powershell.exe
Effective capability sequence:
- CompileCSharp

## 01ac59794106da1524d4d96b5aedf471.deob.ps1
SampleId: `01ac59794106da1524d4d96b5aedf471`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 01c563690ffd0edafc249ecc77a1c9d8.deob.ps1
SampleId: `01c563690ffd0edafc249ecc77a1c9d8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`48`  eligible=`True`  noise=`47`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`8`  byteArrays=`0`  astNodes=`5`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- calc.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 02d82dda8f2750b305b9c0976d559aaf.deob.ps1
SampleId: `02d82dda8f2750b305b9c0976d559aaf`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`5044`  eligible=`True`  noise=`5007`
Actions: normalized=`37`  effective=`37`  actionNoise=`43`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1446`  byteArrays=`0`  astNodes=`1062`  obf=`21`  clarity=`79`
Stubbed: raw=`13`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- get-itemproperty
- test-path
- new-object
- new-object
- test-path
- test-path
- test-path
- test-path
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- new-object
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 035f2018889ce0d07f9f51c796b621a8.deob.ps1
SampleId: `035f2018889ce0d07f9f51c796b621a8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`316`  eligible=`True`  noise=`316`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`277`  byteArrays=`0`  astNodes=`139`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 039e645a7b120f135829b66ab0fe1168.deob.ps1
SampleId: `039e645a7b120f135829b66ab0fe1168`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`177`  eligible=`True`  noise=`174`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`130`  byteArrays=`0`  astNodes=`42`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 05a55983f17e35b0bd96e4c2a6e41fb1.deob.ps1
SampleId: `05a55983f17e35b0bd96e4c2a6e41fb1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`139`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 06fc0104ae06c5642f01921c8f2551d4.deob.ps1
SampleId: `06fc0104ae06c5642f01921c8f2551d4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`39`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 07902bcec912c2211d1da3e48250770f.deob.ps1
SampleId: `07902bcec912c2211d1da3e48250770f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`295`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 07f973763d6669f5c54c425281674665.deob.ps1
SampleId: `07f973763d6669f5c54c425281674665`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`149`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 0853bd493a6d3ff4a703492cabe06897.deob.ps1
SampleId: `0853bd493a6d3ff4a703492cabe06897`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5364`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 087e9b873042f93a5b0454fb387456aa.deob.ps1
SampleId: `087e9b873042f93a5b0454fb387456aa`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`95`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`147`  byteArrays=`0`  astNodes=`28`  obf=`30`  clarity=`70`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
- invoke-item
Recorded important API sequence:
- invoke-webrequest
- invoke-item
Effective important API sequence:
- invoke-webrequest
- invoke-item
Effective capability sequence:
- Download

## 0977710a63aabe53588e0d748195152c.deob.ps1
SampleId: `0977710a63aabe53588e0d748195152c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`128`  eligible=`True`  noise=`126`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`175`  byteArrays=`0`  astNodes=`39`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- start-process
- invoke-webrequest
Recorded important API sequence:
- start-process
- invoke-webrequest
Effective important API sequence:
- start-process
- invoke-webrequest
Effective capability sequence:
- ProcessSpawn
- Download

## 09c74b48746d4485773e5ad2c574b7e3.deob.ps1
SampleId: `09c74b48746d4485773e5ad2c574b7e3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`82`  eligible=`True`  noise=`81`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`172`  byteArrays=`0`  astNodes=`21`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## 0ae8b984348b087ff19ef9d7a0da7f48.deob.ps1
SampleId: `0ae8b984348b087ff19ef9d7a0da7f48`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`452`  eligible=`True`  noise=`450`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`191`  byteArrays=`0`  astNodes=`119`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.IO.DriveInfo.GetDrives
- where-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 0b56d5f0e8b9a40a5763a98ca487242a.deob.ps1
SampleId: `0b56d5f0e8b9a40a5763a98ca487242a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`96`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`75`  byteArrays=`0`  astNodes=`23`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 0d2f54b8a7d8f66476c340e1d0e9db40.deob.ps1
SampleId: `0d2f54b8a7d8f66476c340e1d0e9db40`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`299`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 0d42f972e3863579b7e433f17353f5e4.deob.ps1
SampleId: `0d42f972e3863579b7e433f17353f5e4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`5020`  eligible=`True`  noise=`4983`
Actions: normalized=`37`  effective=`37`  actionNoise=`43`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1432`  byteArrays=`0`  astNodes=`1046`  obf=`21`  clarity=`79`
Stubbed: raw=`13`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- get-itemproperty
- test-path
- new-object
- new-object
- test-path
- test-path
- test-path
- test-path
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- new-object
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 0dd1e531ff257340e037a25097254aef.deob.ps1
SampleId: `0dd1e531ff257340e037a25097254aef`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`335`  eligible=`True`  noise=`331`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`318`  byteArrays=`0`  astNodes=`119`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 0e99a36e7339652aa27d9465c8fdc3a2.deob.ps1
SampleId: `0e99a36e7339652aa27d9465c8fdc3a2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`30`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 0f087ab12f9c986e06200ed5ba9d3bb0.deob.ps1
SampleId: `0f087ab12f9c986e06200ed5ba9d3bb0`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`575`  eligible=`True`  noise=`570`
Actions: normalized=`5`  effective=`5`  actionNoise=`1`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`85`  byteArrays=`0`  astNodes=`24`  obf=`12`  clarity=`88`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- cmd.exe
Recorded important API sequence:
- add-type
- cmd.exe
Effective important API sequence:
- add-type
- cmd.exe
Effective capability sequence:
- CompileCSharp

## 0f8ee4ab3a5017e69a41ee5be221214a.deob.ps1
SampleId: `0f8ee4ab3a5017e69a41ee5be221214a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`96`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 0fa1ae49f32c68c2973a19f85668e35c.deob.ps1
SampleId: `0fa1ae49f32c68c2973a19f85668e35c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2233`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 0fc9392a25646d53386bea7ac2f367d8.deob.ps1
SampleId: `0fc9392a25646d53386bea7ac2f367d8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`591`  eligible=`True`  noise=`571`
Actions: normalized=`20`  effective=`20`  actionNoise=`0`
Important APIs: recorded=`7`  effective=`7`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`858`  byteArrays=`0`  astNodes=`138`  obf=`20`  clarity=`80`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- set-alias
- nZXA
- System.String.Replace
- System.String.Replace
- System.String.Replace
- System.String.Replace
- invoke-expression
- new-object
- System.String.Replace
- System.String.Replace
- System.String.Replace
- System.Net.WebClient.DownloadFile
- System.String.Replace
- invoke-expression
- nZXA
- invoke-expression
- new-object
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Recorded important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Effective important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Effective capability sequence:
- ScriptExec
- Download

## 100f49226c2388dd067a9bbe7485d1fb.deob.ps1
SampleId: `100f49226c2388dd067a9bbe7485d1fb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`48`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 101d053b0094b3f6f20d311c00e6f09c.deob.ps1
SampleId: `101d053b0094b3f6f20d311c00e6f09c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`63`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 10a79e9c2148f359ba6b2accdacf37ec.deob.ps1
SampleId: `10a79e9c2148f359ba6b2accdacf37ec`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`738`  eligible=`True`  noise=`734`
Actions: normalized=`4`  effective=`4`  actionNoise=`1`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`1`  strings=`969`  byteArrays=`0`  astNodes=`503`  obf=`10`  clarity=`90`
Stubbed: raw=`2`  normalized=`1`  important=`0`  coverage=`fallback_appended`
Stubbed sinks: Win32Functions.Win32.CreateThread, start-sleep
Effective action sequence:
- add-type
- Win32Functions.Win32.VirtualAlloc
- System.IntPtr.ToInt32
- Win32Functions.Win32.CreateThread
Recorded important API sequence:
- add-type
Effective important API sequence:
- add-type
Effective capability sequence:
- CompileCSharp
- RemoteMemoryAlloc
- RemoteThreadCreate

## 1374f077f74fda35514dd75da36130da.deob.ps1
SampleId: `1374f077f74fda35514dd75da36130da`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`31`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 14b7062400764200af54e9f3506cc1d8.deob.ps1
SampleId: `14b7062400764200af54e9f3506cc1d8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`419`  eligible=`True`  noise=`419`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`992`  byteArrays=`0`  astNodes=`390`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 14e9328700435020210da81037259798.deob.ps1
SampleId: `14e9328700435020210da81037259798`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`100`  eligible=`True`  noise=`100`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`190`  byteArrays=`0`  astNodes=`33`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 157d0d31e7dfe854160148284b5298d8.deob.ps1
SampleId: `157d0d31e7dfe854160148284b5298d8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`68`  eligible=`True`  noise=`68`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`7`  effective=`7`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`1`  strings=`4044`  byteArrays=`0`  astNodes=`1383`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteThreadCreate
- RemoteProcessOpen
- RemoteMemoryAlloc
- RemoteMemoryWrite
- CompileCSharp
- ShellcodeInject
- ProcessSpawn

## 16632285ebcc1d28c4b6f9c8eb94621e.deob.ps1
SampleId: `16632285ebcc1d28c4b6f9c8eb94621e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`57`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 16912bab54f0bdb722f243096b9990f1.deob.ps1
SampleId: `16912bab54f0bdb722f243096b9990f1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2221`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 16fbb95d35e405bfdb2551c3778a549e.deob.ps1
SampleId: `16fbb95d35e405bfdb2551c3778a549e`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`538`  eligible=`True`  noise=`534`
Actions: normalized=`4`  effective=`4`  actionNoise=`1`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`64`  byteArrays=`0`  astNodes=`9`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
Recorded important API sequence:
- add-type
Effective important API sequence:
- add-type
Effective capability sequence:
- CompileCSharp

## 175ee32d042c2f1e958100d13442410b.deob.ps1
SampleId: `175ee32d042c2f1e958100d13442410b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`253`  eligible=`True`  noise=`237`
Actions: normalized=`16`  effective=`16`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`133`  byteArrays=`0`  astNodes=`60`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- NETSTAT.EXE
- foreach-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- group-object
- System.Management.Automation.Internal.Host.InternalHostUserInterface.WriteLine
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 17cdd05fa8763b7869ec594ce80e8df9.deob.ps1
SampleId: `17cdd05fa8763b7869ec594ce80e8df9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`100`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 18a95acf9cb471c3d24cabdf50d3f2b7.deob.ps1
SampleId: `18a95acf9cb471c3d24cabdf50d3f2b7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`289`  eligible=`True`  noise=`285`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`218`  byteArrays=`0`  astNodes=`82`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Net.WebRequest.GetSystemWebProxy
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 190349afef1c584473717f402fc099ec.deob.ps1
SampleId: `190349afef1c584473717f402fc099ec`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`194`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 1bf71e4576dde0f8e2c8c07cc7049af3.deob.ps1
SampleId: `1bf71e4576dde0f8e2c8c07cc7049af3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`568`  eligible=`True`  noise=`564`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`3`  effective=`4`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`1`  strings=`845`  byteArrays=`0`  astNodes=`355`  obf=`10`  clarity=`90`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- new-object
- System.Net.WebRequest.GetSystemWebProxy
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Effective capability sequence:
- Download
- RemoteMemoryAlloc
- RemoteThreadCreate
- CompileCSharp

## 1c0d56a9f235820339b20b5fead169b2.deob.ps1
SampleId: `1c0d56a9f235820339b20b5fead169b2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5332`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 1c21f2ea07bce442f55a84999687bb96.deob.ps1
SampleId: `1c21f2ea07bce442f55a84999687bb96`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`59`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 1dc520a66d4b83b02d1abc207e8e23f5.deob.ps1
SampleId: `1dc520a66d4b83b02d1abc207e8e23f5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2233`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 1dee780fb11e5dfdaacd3f0c5c908c4f.deob.ps1
SampleId: `1dee780fb11e5dfdaacd3f0c5c908c4f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2393`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 21081c6ff43ae43c08f750ea20280713.deob.ps1
SampleId: `21081c6ff43ae43c08f750ea20280713`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`143`  eligible=`True`  noise=`142`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`117`  byteArrays=`0`  astNodes=`15`  obf=`12`  clarity=`88`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- powershell.exe
Recorded important API sequence:
- powershell.exe
Effective important API sequence:
- powershell.exe
Effective capability sequence:
- ProcessSpawn

## 214e58b2ca107d11c6c0d6b7a28312ab.deob.ps1
SampleId: `214e58b2ca107d11c6c0d6b7a28312ab`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`513`  eligible=`True`  noise=`513`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`197`  byteArrays=`0`  astNodes=`138`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 2181d9c83a4095edd990d90031ae94d9.deob.ps1
SampleId: `2181d9c83a4095edd990d90031ae94d9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`51`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 21c4cc550f1c97569a2e102fd691ea0c.deob.ps1
SampleId: `21c4cc550f1c97569a2e102fd691ea0c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`49`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 21eec2ded28ca4bcb10672765a1fdc97.deob.ps1
SampleId: `21eec2ded28ca4bcb10672765a1fdc97`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`50`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 2227628d221a7e164745308640c3ec65.deob.ps1
SampleId: `2227628d221a7e164745308640c3ec65`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 22fccd4cfaa3bee27b30f7e816734b53.deob.ps1
SampleId: `22fccd4cfaa3bee27b30f7e816734b53`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`171`  eligible=`True`  noise=`169`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`71`  byteArrays=`0`  astNodes=`136`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- set-alias
- mshta.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 235fe01a3a61b7c3d2f816a343c82aed.deob.ps1
SampleId: `235fe01a3a61b7c3d2f816a343c82aed`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`170`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 2387aa05b84b680bb51b0cfb3d60f05b.deob.ps1
SampleId: `2387aa05b84b680bb51b0cfb3d60f05b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`83`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 23edc89712effcd118c2271f730d6a51.deob.ps1
SampleId: `23edc89712effcd118c2271f730d6a51`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2413`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 243b887d1cc72ba0789483d2616d2b5b.deob.ps1
SampleId: `243b887d1cc72ba0789483d2616d2b5b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 259156a81c4bd8f5ca3404b2fef02c3e.deob.ps1
SampleId: `259156a81c4bd8f5ca3404b2fef02c3e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`268`  eligible=`True`  noise=`264`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`492`  byteArrays=`0`  astNodes=`72`  obf=`25`  clarity=`75`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe, System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- cmd.exe
- new-object
- System.Net.WebClient.DownloadFile
- get-content
Recorded important API sequence:
- cmd.exe
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- cmd.exe
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ScriptExec

## 271a4e46b2ac491dd0e938c627742419.deob.ps1
SampleId: `271a4e46b2ac491dd0e938c627742419`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`134`  eligible=`True`  noise=`133`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`49`  byteArrays=`0`  astNodes=`31`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-process
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 274b8493cb6ff94bb0aad1c8d833ef2e.deob.ps1
SampleId: `274b8493cb6ff94bb0aad1c8d833ef2e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`403`  eligible=`True`  noise=`399`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`4`  dynExec=`0`  compile=`0`  strings=`1845`  byteArrays=`0`  astNodes=`186`  obf=`45`  clarity=`55`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- test-path
- set-content
- set-content
- cmd.exe
Recorded important API sequence:
- set-content
- set-content
- cmd.exe
Effective important API sequence:
- set-content
- set-content
- cmd.exe
Effective capability sequence:
- FileWrite

## 2785abefe93fd6a969d5f5a2f7e283c2.deob.ps1
SampleId: `2785abefe93fd6a969d5f5a2f7e283c2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`51`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 2892b81283ad9c0e8c7be7e0626dc89a.deob.ps1
SampleId: `2892b81283ad9c0e8c7be7e0626dc89a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`1186`  eligible=`True`  noise=`1184`
Actions: normalized=`2`  effective=`2`  actionNoise=`13`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`865`  byteArrays=`0`  astNodes=`431`  obf=`6`  clarity=`94`
Stubbed: raw=`13`  normalized=`0`  important=`0`  coverage=`complete`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep
Effective action sequence:
- control.exe
- System.Reflection.Assembly.LoadWithPartialName
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 2ab55433c4beddae5a3bc9c2a639d7d2.deob.ps1
SampleId: `2ab55433c4beddae5a3bc9c2a639d7d2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5440`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 2c05d9da78f73acf70b71e0cff5abdb3.deob.ps1
SampleId: `2c05d9da78f73acf70b71e0cff5abdb3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`190`  eligible=`True`  noise=`187`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`356`  byteArrays=`0`  astNodes=`74`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- set-alias
- new-object
- invoke-webrequest
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## 2c2416675787624bd0fe0fc4a5e2a816.deob.ps1
SampleId: `2c2416675787624bd0fe0fc4a5e2a816`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`79`  eligible=`True`  noise=`78`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`83`  byteArrays=`0`  astNodes=`22`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 2ca9023a22c16cca9527d65162134b6c.deob.ps1
SampleId: `2ca9023a22c16cca9527d65162134b6c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2205`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 2ccfc40d9538ce0e41932ebbab56f54e.deob.ps1
SampleId: `2ccfc40d9538ce0e41932ebbab56f54e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`86`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 2f15e4b4a1af8c336cb8f6bc7d4d3077.deob.ps1
SampleId: `2f15e4b4a1af8c336cb8f6bc7d4d3077`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`36`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 2fc6ce741696928e30e67dbd23f6240a.deob.ps1
SampleId: `2fc6ce741696928e30e67dbd23f6240a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`209`  eligible=`True`  noise=`205`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`139`  byteArrays=`0`  astNodes=`46`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebRequest.GetSystemWebProxy
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 3019afd2094c2946a2636dbe75f6cd2d.deob.ps1
SampleId: `3019afd2094c2946a2636dbe75f6cd2d`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`95`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`147`  byteArrays=`0`  astNodes=`28`  obf=`30`  clarity=`70`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
- invoke-item
Recorded important API sequence:
- invoke-webrequest
- invoke-item
Effective important API sequence:
- invoke-webrequest
- invoke-item
Effective capability sequence:
- Download

## 30221edb3cbc493c7d078375fffbd7cf.deob.ps1
SampleId: `30221edb3cbc493c7d078375fffbd7cf`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`89`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 3036630fb4014935c76533ed8db146d1.deob.ps1
SampleId: `3036630fb4014935c76533ed8db146d1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`127`  eligible=`True`  noise=`125`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`145`  byteArrays=`0`  astNodes=`32`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 329508bde7e5b6490df8ec8b2ea91a77.deob.ps1
SampleId: `329508bde7e5b6490df8ec8b2ea91a77`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`20`  byteArrays=`0`  astNodes=`7`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 333e3ce4c9ba2cc4ce4becbaa1a775ad.deob.ps1
SampleId: `333e3ce4c9ba2cc4ce4becbaa1a775ad`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`45`  eligible=`True`  noise=`45`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`7`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 337690d835c5e507923566e9fa094048.deob.ps1
SampleId: `337690d835c5e507923566e9fa094048`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`2872`  eligible=`True`  noise=`2842`
Actions: normalized=`30`  effective=`30`  actionNoise=`31`
Important APIs: recorded=`10`  effective=`10`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`854`  byteArrays=`0`  astNodes=`214`  obf=`20`  clarity=`80`
Stubbed: raw=`3`  normalized=`3`  important=`3`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString, System.Management.Automation.PSObject.DownloadString, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebHeaderCollection.Remove
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Convert.FromBase64String
- invoke-expression
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Convert.FromBase64String
- invoke-expression
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 34349a4a4183e369d2901d5230f1a6df.deob.ps1
SampleId: `34349a4a4183e369d2901d5230f1a6df`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`576`  eligible=`True`  noise=`568`
Actions: normalized=`8`  effective=`8`  actionNoise=`3`
Important APIs: recorded=`4`  effective=`4`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`370`  byteArrays=`0`  astNodes=`169`  obf=`13`  clarity=`87`
Stubbed: raw=`6`  normalized=`3`  important=`3`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 349df1e56670ca1c70727509b4ff427b.deob.ps1
SampleId: `349df1e56670ca1c70727509b4ff427b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`106`  eligible=`True`  noise=`106`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`46`  byteArrays=`0`  astNodes=`30`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 34bc10427e137ff53eb1037b68325692.deob.ps1
SampleId: `34bc10427e137ff53eb1037b68325692`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`606`  eligible=`True`  noise=`600`
Actions: normalized=`6`  effective=`6`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`175`  byteArrays=`0`  astNodes=`46`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- start-bitstransfer
- invoke-item
Recorded important API sequence:
- add-type
- invoke-item
Effective important API sequence:
- add-type
- invoke-item
Effective capability sequence:
- CompileCSharp

## 3515de123d6bf762d48081ca1f51596f.deob.ps1
SampleId: `3515de123d6bf762d48081ca1f51596f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`53`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 359e2f26732dc4c4917f83e51ab0b1ee.deob.ps1
SampleId: `359e2f26732dc4c4917f83e51ab0b1ee`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`149`  eligible=`True`  noise=`147`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`196`  byteArrays=`0`  astNodes=`42`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 35a4cce89bcb813386f34fbe13f4880e.deob.ps1
SampleId: `35a4cce89bcb813386f34fbe13f4880e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`81`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 366b20291453e71d5d56fe08ef012fd2.deob.ps1
SampleId: `366b20291453e71d5d56fe08ef012fd2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`960`  eligible=`True`  noise=`937`
Actions: normalized=`23`  effective=`23`  actionNoise=`3`
Important APIs: recorded=`21`  effective=`21`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`1521`  byteArrays=`0`  astNodes=`456`  obf=`7`  clarity=`93`
Stubbed: raw=`10`  normalized=`10`  important=`10`  coverage=`complete_with_stubbed`
Stubbed sinks: certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe, certutil.exe
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.ScriptBlock.GetSteppablePipeline
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Recorded important API sequence:
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Effective important API sequence:
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- certutil.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Effective capability sequence:
- Download

## 37f7457b33eda31dd5b7ae5be68ad257.deob.ps1
SampleId: `37f7457b33eda31dd5b7ae5be68ad257`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`159`  eligible=`True`  noise=`156`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`49`  byteArrays=`0`  astNodes=`48`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- findstr.exe
- System.Convert.FromBase64String
- System.Reflection.Assembly.Load
Recorded important API sequence:
- System.Reflection.Assembly.Load
Effective important API sequence:
- System.Reflection.Assembly.Load
Effective capability sequence: _(none)_

## 38b0f77fb7d2b0718acd7a992d5a0cb2.deob.ps1
SampleId: `38b0f77fb7d2b0718acd7a992d5a0cb2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`60`  eligible=`True`  noise=`60`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`123`  byteArrays=`0`  astNodes=`8`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 38f98275bfb42bc138ba17b73dbcc44e.deob.ps1
SampleId: `38f98275bfb42bc138ba17b73dbcc44e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`382`  eligible=`True`  noise=`379`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`276`  byteArrays=`0`  astNodes=`73`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- Add-RegistryValue
- test-path
- set-itemproperty
Recorded important API sequence:
- set-itemproperty
Effective important API sequence:
- set-itemproperty
Effective capability sequence:
- RegistryModify

## 3949847e35dfe1af9bb4529ee9c53a33.deob.ps1
SampleId: `3949847e35dfe1af9bb4529ee9c53a33`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`68`  eligible=`True`  noise=`67`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`65`  byteArrays=`0`  astNodes=`25`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 398df4dad14d5ec830c7c4e645610375.deob.ps1
SampleId: `398df4dad14d5ec830c7c4e645610375`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`601`  eligible=`True`  noise=`599`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1374`  byteArrays=`0`  astNodes=`186`  obf=`21`  clarity=`79`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- test-path
- get-childitem
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 3c13c79a62e711811951965f4cfb3369.deob.ps1
SampleId: `3c13c79a62e711811951965f4cfb3369`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 3c4e8a00fcaae5015bc5fa1ce10ad263.deob.ps1
SampleId: `3c4e8a00fcaae5015bc5fa1ce10ad263`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`2083`  eligible=`True`  noise=`2082`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`719`  byteArrays=`1`  astNodes=`7192`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- test-path
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- FileWrite

## 3cc6cc1354c3c2d01cb6e638c671e802.deob.ps1
SampleId: `3cc6cc1354c3c2d01cb6e638c671e802`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`222`  eligible=`True`  noise=`218`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`340`  byteArrays=`0`  astNodes=`74`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebProxy.GetDefaultProxy
- System.Net.WebClient.DownloadFile
- rename-item
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
- rename-item
Effective important API sequence:
- System.Net.WebClient.DownloadFile
- rename-item
Effective capability sequence:
- Download
- ProcessSpawn

## 3d0d3d8ab486f5312a44947127630a7e.deob.ps1
SampleId: `3d0d3d8ab486f5312a44947127630a7e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5448`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 3d5b6c3a3af088572fbbc6b77cbc4739.deob.ps1
SampleId: `3d5b6c3a3af088572fbbc6b77cbc4739`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`343`  eligible=`True`  noise=`338`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`141`  byteArrays=`0`  astNodes=`86`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.Start
Effective action sequence:
- new-object
- new-object
- System.Diagnostics.Process.Start
- System.Management.Automation.PSObject.AcceptTcpClient
- System.Management.Automation.PSObject.Stop
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn

## 3e18ae0aefce94e69f19b16a27013df5.deob.ps1
SampleId: `3e18ae0aefce94e69f19b16a27013df5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`744`  eligible=`True`  noise=`739`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`577`  byteArrays=`0`  astNodes=`218`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- new-object
- System.Net.WebClient.DownloadString
- System.Convert.FromBase64String
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 3e9b4f55134a50bd08ea14a7a057fc93.deob.ps1
SampleId: `3e9b4f55134a50bd08ea14a7a057fc93`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`39`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 3f87dd4d67fbc3d426dc3f6530c235f9.deob.ps1
SampleId: `3f87dd4d67fbc3d426dc3f6530c235f9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`209`  eligible=`True`  noise=`204`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`4`  effective=`4`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`218`  byteArrays=`0`  astNodes=`49`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- get-content
- set-itemproperty
- remove-item
- remove-item
- remove-item
Recorded important API sequence:
- set-itemproperty
- remove-item
- remove-item
- remove-item
Effective important API sequence:
- set-itemproperty
- remove-item
- remove-item
- remove-item
Effective capability sequence:
- RegistryModify

## 3fad375a96cce6f59eba61772e40ac3a.deob.ps1
SampleId: `3fad375a96cce6f59eba61772e40ac3a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`367`  eligible=`True`  noise=`363`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`394`  byteArrays=`0`  astNodes=`148`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 3fb6ef148a07919012bebf7bebfabe7e.deob.ps1
SampleId: `3fb6ef148a07919012bebf7bebfabe7e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 3fef5d49e63459083e427835e2de9311.deob.ps1
SampleId: `3fef5d49e63459083e427835e2de9311`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `unsafe_timeout`
Instructions: source=`instruction_list`  count=`555`  eligible=`False`  noise=`553`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`416`  byteArrays=`0`  astNodes=`194`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Stubbed sinks: start-sleep
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
Effective capability sequence:
- ScriptExec

## 40a29f7aab0b55f7bc2ea51d2b15eb36.deob.ps1
SampleId: `40a29f7aab0b55f7bc2ea51d2b15eb36`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`363`  eligible=`True`  noise=`359`
Actions: normalized=`4`  effective=`4`  actionNoise=`3`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`220`  byteArrays=`0`  astNodes=`45`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.ScriptBlock.GetSteppablePipeline
- invoke-webrequest
- msiexec.exe
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## 41534a52301d781428bd68fc7d1760d9.deob.ps1
SampleId: `41534a52301d781428bd68fc7d1760d9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 43d307b43168d347745ecf8578e8aeea.deob.ps1
SampleId: `43d307b43168d347745ecf8578e8aeea`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`92`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 43df228efe5bdb252f1e808dc3e355cd.deob.ps1
SampleId: `43df228efe5bdb252f1e808dc3e355cd`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`94`  eligible=`True`  noise=`94`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`136`  byteArrays=`0`  astNodes=`28`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 44d9357676b23948a73741a5250f2d91.deob.ps1
SampleId: `44d9357676b23948a73741a5250f2d91`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2233`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 495e15b91a46fc465cedb59fe1f30a50.deob.ps1
SampleId: `495e15b91a46fc465cedb59fe1f30a50`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`188`  eligible=`True`  noise=`185`
Actions: normalized=`3`  effective=`3`  actionNoise=`2`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`160`  byteArrays=`0`  astNodes=`77`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- foreach-object
- get-childitem
- get-childitem
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 49a6ee5be6759b4fc872dc9da9bf4cb6.deob.ps1
SampleId: `49a6ee5be6759b4fc872dc9da9bf4cb6`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`43`  byteArrays=`0`  astNodes=`12`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- Download

## 4a41b0d892f08b16aa5e68ee9541abb4.deob.ps1
SampleId: `4a41b0d892f08b16aa5e68ee9541abb4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`45`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 4a6a9e9fa95c601745cb33f06f7bf97a.deob.ps1
SampleId: `4a6a9e9fa95c601745cb33f06f7bf97a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`7730`  eligible=`True`  noise=`7693`
Actions: normalized=`37`  effective=`37`  actionNoise=`5`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`430`  byteArrays=`0`  astNodes=`80`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
- convertfrom-stringdata
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- test-path
- GetResolvedPathHelper
- resolve-path
- resolve-path
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- ProgressBarHelper
- write-progress
- GetResolvedPathHelper
- resolve-path
- ValidateArchivePathHelper
- System.IO.File.Exists
- ThrowTerminatingErrorHelper
- new-object
- new-object
- new-object
- System.Management.Automation.PSScriptCmdlet.ThrowTerminatingError
- ExpandArchiveHelper
- Add-CompressionAssemblies
- add-type
- add-type
- System.String.EndsWith
- join-path
- System.Management.Automation.PathIntrinsics.GetUnresolvedProviderPathFromPSPath
- System.String.StartsWith
- System.IO.Path.GetExtension
- new-object
- test-path
- System.String.Split
- foreach-object
- System.Management.Automation.PSObject.Trim
- System.String.Join
- ProgressBarHelper
- write-progress
Recorded important API sequence:
- invoke-webrequest
- add-type
- add-type
Effective important API sequence:
- invoke-webrequest
- add-type
- add-type
Effective capability sequence:
- Download
- CompileCSharp

## 4aa2395748255f7d3549e27c60d15531.deob.ps1
SampleId: `4aa2395748255f7d3549e27c60d15531`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`301`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 4b280b5dc3efd82cd4538ec8f5638784.deob.ps1
SampleId: `4b280b5dc3efd82cd4538ec8f5638784`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`297`  eligible=`True`  noise=`297`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`224`  byteArrays=`0`  astNodes=`90`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 4c3847ceeb3c5cdde9bf7795bf0aeebe.deob.ps1
SampleId: `4c3847ceeb3c5cdde9bf7795bf0aeebe`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`7930`  eligible=`True`  noise=`7888`
Actions: normalized=`42`  effective=`42`  actionNoise=`7`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`387`  byteArrays=`0`  astNodes=`156`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- get-childitem
- where-object
- System.IO.File.ReadAllBytes
- convertfrom-stringdata
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- test-path
- GetResolvedPathHelper
- resolve-path
- resolve-path
- System.Management.Automation.PSBoundParametersDictionary.ContainsKey
- ProgressBarHelper
- write-progress
- GetResolvedPathHelper
- resolve-path
- ValidateArchivePathHelper
- System.IO.File.Exists
- ThrowTerminatingErrorHelper
- new-object
- new-object
- new-object
- System.Management.Automation.PSScriptCmdlet.ThrowTerminatingError
- out-null
- ExpandArchiveHelper
- Add-CompressionAssemblies
- add-type
- add-type
- System.String.EndsWith
- join-path
- System.Management.Automation.PathIntrinsics.GetUnresolvedProviderPathFromPSPath
- System.String.StartsWith
- System.IO.Path.GetExtension
- new-object
- test-path
- System.String.Split
- foreach-object
- System.Management.Automation.PSObject.Trim
- System.String.Join
- out-null
- ProgressBarHelper
- write-progress
- remove-item
Recorded important API sequence:
- add-type
- add-type
- remove-item
Effective important API sequence:
- add-type
- add-type
- remove-item
Effective capability sequence:
- CompileCSharp

## 4c89b4cce0c93e2d6edc6ec818b39e0f.deob.ps1
SampleId: `4c89b4cce0c93e2d6edc6ec818b39e0f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`88`  eligible=`True`  noise=`87`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`623`  byteArrays=`0`  astNodes=`40`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## 4cfc245d0028828c0dba7b4c92c97f95.deob.ps1
SampleId: `4cfc245d0028828c0dba7b4c92c97f95`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`123`  eligible=`True`  noise=`121`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`88`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download

## 4ee32284e4d2b7accfaf28637d569bb3.deob.ps1
SampleId: `4ee32284e4d2b7accfaf28637d569bb3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`98`  eligible=`True`  noise=`98`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`135`  byteArrays=`0`  astNodes=`31`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 4f410632f9ac4ee0c95be952eb405ccc.deob.ps1
SampleId: `4f410632f9ac4ee0c95be952eb405ccc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`90`  eligible=`True`  noise=`88`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`68`  byteArrays=`0`  astNodes=`21`  obf=`20`  clarity=`80`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- System.IO.File.ReadAllLines
- powershell.exe
Recorded important API sequence:
- powershell.exe
Effective important API sequence:
- powershell.exe
Effective capability sequence: _(none)_

## 507cb233e9bfd88c38e15fd313c078b2.deob.ps1
SampleId: `507cb233e9bfd88c38e15fd313c078b2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`88`  eligible=`True`  noise=`87`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`791`  byteArrays=`0`  astNodes=`40`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## 50b73b5edf92deb4d362881b87479230.deob.ps1
SampleId: `50b73b5edf92deb4d362881b87479230`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`305`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 51df1aec7cf187cd7fb8e85c23555736.deob.ps1
SampleId: `51df1aec7cf187cd7fb8e85c23555736`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`42`  byteArrays=`0`  astNodes=`6`  obf=`12`  clarity=`88`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 52ecbc7debdf6661120f4f2949a15555.deob.ps1
SampleId: `52ecbc7debdf6661120f4f2949a15555`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`14`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- write-output
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 533115594ff41dc04da443ab5151a36c.deob.ps1
SampleId: `533115594ff41dc04da443ab5151a36c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`74`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 541d593daa1a55ba2fa992015f5cfb2e.deob.ps1
SampleId: `541d593daa1a55ba2fa992015f5cfb2e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`1004`  eligible=`True`  noise=`998`
Actions: normalized=`6`  effective=`6`  actionNoise=`3`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`3103`  byteArrays=`0`  astNodes=`169`  obf=`9`  clarity=`91`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- write-host
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.ScriptBlock.GetSteppablePipeline
- out-null
- invoke-webrequest
- regsvr32.exe
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## 544e9826b126f2ed3cc3e9a7e51ab6c7.deob.ps1
SampleId: `544e9826b126f2ed3cc3e9a7e51ab6c7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 544fc0c97554e9614f6b0af7b9808193.deob.ps1
SampleId: `544fc0c97554e9614f6b0af7b9808193`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`352`  eligible=`True`  noise=`348`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`361`  byteArrays=`0`  astNodes=`132`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 550cbb84f6a7778376b5c02d10728808.deob.ps1
SampleId: `550cbb84f6a7778376b5c02d10728808`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`538`  eligible=`True`  noise=`534`
Actions: normalized=`4`  effective=`4`  actionNoise=`1`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`66`  byteArrays=`0`  astNodes=`9`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
Recorded important API sequence:
- add-type
Effective important API sequence:
- add-type
Effective capability sequence:
- CompileCSharp

## 55537e6f59bdd0a8e6e4723447ea23a7.deob.ps1
SampleId: `55537e6f59bdd0a8e6e4723447ea23a7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`41`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 56072be0f4fd650eee04a355a5db0ce4.deob.ps1
SampleId: `56072be0f4fd650eee04a355a5db0ce4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`44`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 56ae1c5dc8995dde50f383aad88beaf4.deob.ps1
SampleId: `56ae1c5dc8995dde50f383aad88beaf4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`64`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 5785060a024a0179d716c70a02f53ed3.deob.ps1
SampleId: `5785060a024a0179d716c70a02f53ed3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`93`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 58c4c50ec5676c00080433ac11a6d751.deob.ps1
SampleId: `58c4c50ec5676c00080433ac11a6d751`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`225`  eligible=`True`  noise=`224`
Actions: normalized=`1`  effective=`1`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`812`  byteArrays=`0`  astNodes=`190`  obf=`18`  clarity=`82`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-host
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 59bc28b51eb85d5f3386029738fcab1a.deob.ps1
SampleId: `59bc28b51eb85d5f3386029738fcab1a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`1015`  eligible=`True`  noise=`1009`
Actions: normalized=`6`  effective=`6`  actionNoise=`3`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`3898`  byteArrays=`0`  astNodes=`178`  obf=`9`  clarity=`91`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- write-host
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.ScriptBlock.GetSteppablePipeline
- out-null
- invoke-webrequest
- regsvr32.exe
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## 5aeaaadbe1245ce0c7a4b9a1a03f9ef8.deob.ps1
SampleId: `5aeaaadbe1245ce0c7a4b9a1a03f9ef8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2249`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 5b23ae8f2ac54b84acb636db80bd08e5.deob.ps1
SampleId: `5b23ae8f2ac54b84acb636db80bd08e5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`91`  eligible=`True`  noise=`91`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`234`  byteArrays=`0`  astNodes=`16`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- Download

## 5b38e93016b2f9121f6396bed8a98709.deob.ps1
SampleId: `5b38e93016b2f9121f6396bed8a98709`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`119`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 5bf449b90106a647fca2589233802685.deob.ps1
SampleId: `5bf449b90106a647fca2589233802685`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`43`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 5c6170ea7dc56da3e8c260a5a9498aef.deob.ps1
SampleId: `5c6170ea7dc56da3e8c260a5a9498aef`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 5d4bda6c8715fda47638f7853116e216.deob.ps1
SampleId: `5d4bda6c8715fda47638f7853116e216`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`97`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`157`  byteArrays=`0`  astNodes=`30`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 5e1640f4553607d0db72df448082c6be.deob.ps1
SampleId: `5e1640f4553607d0db72df448082c6be`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`257`  eligible=`True`  noise=`252`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`289`  byteArrays=`0`  astNodes=`68`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebRequest.GetSystemWebProxy
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 5e44430badfec1630be970d9be0ac9a2.deob.ps1
SampleId: `5e44430badfec1630be970d9be0ac9a2`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`455`  eligible=`True`  noise=`449`
Actions: normalized=`6`  effective=`6`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`564`  byteArrays=`0`  astNodes=`97`  obf=`31`  clarity=`69`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- test-path
- new-object
- System.Net.WebClient.DownloadFile
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 5eab0a90b7257e43d19dc2047ffa3dd3.deob.ps1
SampleId: `5eab0a90b7257e43d19dc2047ffa3dd3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`430`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 5eb8378f1430c5d6d2ca95ac4511a5a5.deob.ps1
SampleId: `5eb8378f1430c5d6d2ca95ac4511a5a5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`58`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 5ee0c582f7b50fe00abf8120f65d2f97.deob.ps1
SampleId: `5ee0c582f7b50fe00abf8120f65d2f97`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`20`  byteArrays=`0`  astNodes=`11`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- remove-item
Recorded important API sequence:
- remove-item
Effective important API sequence:
- remove-item
Effective capability sequence: _(none)_

## 5f1d010a5d3761962827f0853c1b0556.deob.ps1
SampleId: `5f1d010a5d3761962827f0853c1b0556`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`93`  byteArrays=`0`  astNodes=`26`  obf=`31`  clarity=`69`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 5f359bb2d594e3e2af1518baf878ce69.deob.ps1
SampleId: `5f359bb2d594e3e2af1518baf878ce69`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`95`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`121`  byteArrays=`0`  astNodes=`28`  obf=`24`  clarity=`76`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-restmethod
Effective action sequence:
- invoke-restmethod
- invoke-item
Recorded important API sequence:
- invoke-restmethod
- invoke-item
Effective important API sequence:
- invoke-restmethod
- invoke-item
Effective capability sequence:
- Download

## 5f8df5306a0b2f37aef04bc3f5f632a0.deob.ps1
SampleId: `5f8df5306a0b2f37aef04bc3f5f632a0`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`299`  eligible=`True`  noise=`293`
Actions: normalized=`6`  effective=`6`  actionNoise=`0`
Important APIs: recorded=`6`  effective=`6`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`511`  byteArrays=`0`  astNodes=`166`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- new-itemproperty
- new-itemproperty
- remove-item
Recorded important API sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- new-itemproperty
- new-itemproperty
- remove-item
Effective important API sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- new-itemproperty
- new-itemproperty
- remove-item
Effective capability sequence:
- RegistryModify

## 5fd72c60eb560c4b12d7ca7acf957e6f.deob.ps1
SampleId: `5fd72c60eb560c4b12d7ca7acf957e6f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 600b1ef719a47218ad3535ba1a69164b.deob.ps1
SampleId: `600b1ef719a47218ad3535ba1a69164b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`127`  eligible=`True`  noise=`125`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`103`  byteArrays=`0`  astNodes=`32`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 60882b06ae402e0d7abaf55f3833bc88.deob.ps1
SampleId: `60882b06ae402e0d7abaf55f3833bc88`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2245`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 6108a251a3dbf42895fd43f97ffa1ed8.deob.ps1
SampleId: `6108a251a3dbf42895fd43f97ffa1ed8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`47`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 6115ddaa991c5003cf9e531d4f4df4a4.deob.ps1
SampleId: `6115ddaa991c5003cf9e531d4f4df4a4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2257`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 620401c4a2095ffaa9a2dbd28ba8d336.deob.ps1
SampleId: `620401c4a2095ffaa9a2dbd28ba8d336`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`149`  eligible=`True`  noise=`147`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`162`  byteArrays=`0`  astNodes=`44`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 62707d7de7c6334d868870250caf7b6a.deob.ps1
SampleId: `62707d7de7c6334d868870250caf7b6a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`75`  eligible=`True`  noise=`75`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`17`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 628674ba534d460dc8a551793b07b3ae.deob.ps1
SampleId: `628674ba534d460dc8a551793b07b3ae`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`61`  eligible=`True`  noise=`59`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`60`  byteArrays=`0`  astNodes=`14`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
- invoke-expression
Recorded important API sequence:
- invoke-webrequest
- invoke-expression
Effective important API sequence:
- invoke-webrequest
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 62a8526fa690ba079aa3a576ceaa0aaa.deob.ps1
SampleId: `62a8526fa690ba079aa3a576ceaa0aaa`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`48`  eligible=`True`  noise=`48`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`1`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`23`  byteArrays=`0`  astNodes=`5`  obf=`30`  clarity=`70`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 630a9b69e8d9ccabb97458b7fd5ae240.deob.ps1
SampleId: `630a9b69e8d9ccabb97458b7fd5ae240`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2305`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 65710935c120cedfe7000fe30a67f25b.deob.ps1
SampleId: `65710935c120cedfe7000fe30a67f25b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `unsafe_timeout`
Instructions: source=`instruction_list`  count=`283`  eligible=`False`  noise=`283`
Actions: normalized=`0`  effective=`0`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`291`  byteArrays=`0`  astNodes=`99`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`0`  important=`0`  coverage=`complete`
Stubbed sinks: start-sleep
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 66d5c711c21a67f371b8bf95450c4cd9.deob.ps1
SampleId: `66d5c711c21a67f371b8bf95450c4cd9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`33`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- rundll32.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 67165204eb3d337617dbf08864794d25.deob.ps1
SampleId: `67165204eb3d337617dbf08864794d25`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 672aa0532feb4e41abed3298d60992d9.deob.ps1
SampleId: `672aa0532feb4e41abed3298d60992d9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 6819bfc4148a6889117e1b289d4faecb.deob.ps1
SampleId: `6819bfc4148a6889117e1b289d4faecb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 6823d4bfa6b3fc9a8b3c73fa64be83cb.deob.ps1
SampleId: `6823d4bfa6b3fc9a8b3c73fa64be83cb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`82`  byteArrays=`0`  astNodes=`26`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 698486761f25eff27d2c79228ffba849.deob.ps1
SampleId: `698486761f25eff27d2c79228ffba849`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`99`  eligible=`True`  noise=`99`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`226`  byteArrays=`0`  astNodes=`32`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 69dda0da45e59dd82a442e9792474bef.deob.ps1
SampleId: `69dda0da45e59dd82a442e9792474bef`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`80`  eligible=`True`  noise=`79`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`619`  byteArrays=`0`  astNodes=`38`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## 6a3e52e4fcb6c7ac808c0d60f9589f45.deob.ps1
SampleId: `6a3e52e4fcb6c7ac808c0d60f9589f45`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`561`  eligible=`True`  noise=`559`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`674`  byteArrays=`0`  astNodes=`345`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- new-object
- schtasks.exe
Recorded important API sequence:
- schtasks.exe
Effective important API sequence:
- schtasks.exe
Effective capability sequence: _(none)_

## 6a4d5aeed959e706e0e574f15af38ddf.deob.ps1
SampleId: `6a4d5aeed959e706e0e574f15af38ddf`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`98`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6b7613e0a23f20ac9bff857d82eb30ca.deob.ps1
SampleId: `6b7613e0a23f20ac9bff857d82eb30ca`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`106`  eligible=`True`  noise=`106`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`286`  byteArrays=`0`  astNodes=`42`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6babe7699c77a5ad2f760298d6a6d6e4.deob.ps1
SampleId: `6babe7699c77a5ad2f760298d6a6d6e4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`86`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6c1b81c456dc07a65649a36b49192ea3.deob.ps1
SampleId: `6c1b81c456dc07a65649a36b49192ea3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`48`  eligible=`True`  noise=`47`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`11`  byteArrays=`0`  astNodes=`5`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- notepad.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6c8ca9ff64a7e860a46677fd5ee4d131.deob.ps1
SampleId: `6c8ca9ff64a7e860a46677fd5ee4d131`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`211`  eligible=`True`  noise=`208`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`192`  byteArrays=`0`  astNodes=`37`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 6d51fc16070695efab72668bd89e53dc.deob.ps1
SampleId: `6d51fc16070695efab72668bd89e53dc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5520`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 6da1d82f855d65bff5a2ee562f05bf77.deob.ps1
SampleId: `6da1d82f855d65bff5a2ee562f05bf77`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`88`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- mshta.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6dbcba4a0b898ea3bada0a51a9d006d3.deob.ps1
SampleId: `6dbcba4a0b898ea3bada0a51a9d006d3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`105`  eligible=`True`  noise=`105`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`298`  byteArrays=`0`  astNodes=`38`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 6f96dbb43e57620a358f109a8cf80b09.deob.ps1
SampleId: `6f96dbb43e57620a358f109a8cf80b09`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 6fb403d6d4e1cca7e9fe9290aead8182.deob.ps1
SampleId: `6fb403d6d4e1cca7e9fe9290aead8182`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`68`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 6fc21a98eb1fc1c84bd9f5d242f3e5b1.deob.ps1
SampleId: `6fc21a98eb1fc1c84bd9f5d242f3e5b1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`88`  eligible=`True`  noise=`87`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`731`  byteArrays=`0`  astNodes=`40`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## 7099b989ea0b1145d948df0af302d0f1.deob.ps1
SampleId: `7099b989ea0b1145d948df0af302d0f1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`151`  eligible=`True`  noise=`148`
Actions: normalized=`2`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`105`  byteArrays=`0`  astNodes=`28`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`fallback_appended`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- invoke-expression
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadString
Effective capability sequence:
- ScriptExec

## 715bf6ab17e94ce1958ff6dfb1e51e34.deob.ps1
SampleId: `715bf6ab17e94ce1958ff6dfb1e51e34`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`212`  eligible=`True`  noise=`208`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`139`  byteArrays=`0`  astNodes=`46`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- set-executionpolicy
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- set-executionpolicy
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- set-executionpolicy
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 71818433d21020118113f578264fdc8f.deob.ps1
SampleId: `71818433d21020118113f578264fdc8f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2217`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 7298b92a63a0b823704ed5b40c2aed1a.deob.ps1
SampleId: `7298b92a63a0b823704ed5b40c2aed1a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`127`  eligible=`True`  noise=`125`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`176`  byteArrays=`0`  astNodes=`32`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 733ec5d2a93d0baec8f020cbe736e43d.deob.ps1
SampleId: `733ec5d2a93d0baec8f020cbe736e43d`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`694`  eligible=`True`  noise=`687`
Actions: normalized=`7`  effective=`7`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`290`  byteArrays=`0`  astNodes=`64`  obf=`20`  clarity=`80`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- start-bitstransfer
- get-content
- powershell.exe
Recorded important API sequence:
- add-type
- powershell.exe
Effective important API sequence:
- add-type
- powershell.exe
Effective capability sequence:
- CompileCSharp

## 736c75b2cba6d98313c66baefb4c47c4.deob.ps1
SampleId: `736c75b2cba6d98313c66baefb4c47c4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`105`  eligible=`True`  noise=`105`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`289`  byteArrays=`0`  astNodes=`38`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 749356832d0173e14456f5b682f2d8c4.deob.ps1
SampleId: `749356832d0173e14456f5b682f2d8c4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2257`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 766699e949bb7854f18df4e148681a9c.deob.ps1
SampleId: `766699e949bb7854f18df4e148681a9c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`49`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 770cd9273a327294dff72e3f48b1663a.deob.ps1
SampleId: `770cd9273a327294dff72e3f48b1663a`
Mode: `deob -> deob`  Normalize: `failed (depth 0)`  Safety: `unsafe_normalize_failed`
Instructions: source=`instruction_list`  count=`0`  eligible=`False`  noise=`0`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`122`  byteArrays=`0`  astNodes=`24`  obf=`19`  clarity=`81`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
**Error:** normalize_failed: Unexpected token '3333333333`" < `"\\.\`""' in expression or statement.; Missing closing ')' in expression.
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 7738b915274555e3376b2f4d76b867b2.deob.ps1
SampleId: `7738b915274555e3376b2f4d76b867b2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`1305`  eligible=`True`  noise=`1300`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`681`  byteArrays=`0`  astNodes=`345`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- Invoke-PowerShellTcp
- foreach-object
- System.Text.ASCIIEncoding+ASCIIEncodingSealed.GetBytes
- get-location
- System.Text.ASCIIEncoding+ASCIIEncodingSealed.GetBytes
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 77991a0305285339ea879fba06ef6c31.deob.ps1
SampleId: `77991a0305285339ea879fba06ef6c31`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`85`  eligible=`True`  noise=`85`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`38`  byteArrays=`0`  astNodes=`19`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 77cc7a93ae99a35642722535180bfc0e.deob.ps1
SampleId: `77cc7a93ae99a35642722535180bfc0e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`121`  eligible=`True`  noise=`118`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`0`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`164`  byteArrays=`0`  astNodes=`39`  obf=`6`  clarity=`94`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Net.WebClient.DownloadFile
- System.Diagnostics.Process.Start
Effective capability sequence:
- Download
- ProcessSpawn

## 782757cc796e7130ed8800270b70a762.deob.ps1
SampleId: `782757cc796e7130ed8800270b70a762`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`229`  eligible=`True`  noise=`225`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`218`  byteArrays=`0`  astNodes=`71`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 7898e37b0411dbd23b3d47803fcb5f24.deob.ps1
SampleId: `7898e37b0411dbd23b3d47803fcb5f24`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`36`  byteArrays=`0`  astNodes=`7`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 78d9aad3e3f246801b50fb476bb6f3c4.deob.ps1
SampleId: `78d9aad3e3f246801b50fb476bb6f3c4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`618`  eligible=`True`  noise=`613`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`1467`  byteArrays=`0`  astNodes=`368`  obf=`19`  clarity=`81`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- test-path
- test-path
- test-path
- test-path
- get-host
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 7997f5928ea7b2af3aba81a59468acc9.deob.ps1
SampleId: `7997f5928ea7b2af3aba81a59468acc9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`246`  eligible=`True`  noise=`243`
Actions: normalized=`3`  effective=`3`  actionNoise=`1`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`189`  byteArrays=`0`  astNodes=`73`  obf=`6`  clarity=`94`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest, invoke-webrequest
Effective action sequence:
- new-item
- invoke-webrequest
- invoke-webrequest
Recorded important API sequence:
- new-item
- invoke-webrequest
- invoke-webrequest
Effective important API sequence:
- new-item
- invoke-webrequest
- invoke-webrequest
Effective capability sequence:
- Download
- ProcessSpawn

## 7a164356298bd998a290d09c7ae87ca1.deob.ps1
SampleId: `7a164356298bd998a290d09c7ae87ca1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`77`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 7b2a36da1c9118654333ac64e9ad7f00.deob.ps1
SampleId: `7b2a36da1c9118654333ac64e9ad7f00`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`29`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- mshta.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 7d2ee7bb33d2f59951af5ff8f6a0b0b8.deob.ps1
SampleId: `7d2ee7bb33d2f59951af5ff8f6a0b0b8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`53`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 7e44b4fdfc68b980ebc21322f3caffd4.deob.ps1
SampleId: `7e44b4fdfc68b980ebc21322f3caffd4`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`24`  byteArrays=`0`  astNodes=`6`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 7ea6a2c309f48d64282b6249a12a55fc.deob.ps1
SampleId: `7ea6a2c309f48d64282b6249a12a55fc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`2578`  eligible=`True`  noise=`2562`
Actions: normalized=`16`  effective=`16`  actionNoise=`31`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`374`  byteArrays=`0`  astNodes=`89`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 7fa788e0bf8b833c7d7bc527dd502bf4.deob.ps1
SampleId: `7fa788e0bf8b833c7d7bc527dd502bf4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2217`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 80d01e9b23df3e6dab6ed739549dcbda.deob.ps1
SampleId: `80d01e9b23df3e6dab6ed739549dcbda`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`1242`  eligible=`True`  noise=`1178`
Actions: normalized=`64`  effective=`64`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`548`  byteArrays=`0`  astNodes=`172`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-childitem
- foreach-object
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-childitem
- foreach-object
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
- get-itemproperty
- where-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 81674dfe472e1b71fea0115ae14c4163.deob.ps1
SampleId: `81674dfe472e1b71fea0115ae14c4163`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`80`  eligible=`True`  noise=`79`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`627`  byteArrays=`0`  astNodes=`38`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## 8240dc8d2ea512f1ea7756688a57f513.deob.ps1
SampleId: `8240dc8d2ea512f1ea7756688a57f513`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`68`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 8283e2cb7e47379bf537bc26e963d22b.deob.ps1
SampleId: `8283e2cb7e47379bf537bc26e963d22b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`60`  eligible=`True`  noise=`60`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`43`  byteArrays=`0`  astNodes=`8`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 83856cbb80780fe9b47b45d1de7223ed.deob.ps1
SampleId: `83856cbb80780fe9b47b45d1de7223ed`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`381`  eligible=`True`  noise=`374`
Actions: normalized=`7`  effective=`7`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`206`  byteArrays=`0`  astNodes=`90`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
- new-object
- System.Net.WebClient.DownloadString
- System.Convert.FromBase64String
- foreach-object
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 839c25c58e991207d5b75a67fa2329fb.deob.ps1
SampleId: `839c25c58e991207d5b75a67fa2329fb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`317`  eligible=`True`  noise=`310`
Actions: normalized=`7`  effective=`7`  actionNoise=`2`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`209`  byteArrays=`0`  astNodes=`91`  obf=`13`  clarity=`87`
Stubbed: raw=`3`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- get-childitem
- set-executionpolicy
- get-childitem
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
- get-childitem
Recorded important API sequence:
- set-executionpolicy
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- set-executionpolicy
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 8409ed15a9e5635793887cd48414db7b.deob.ps1
SampleId: `8409ed15a9e5635793887cd48414db7b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 858c6f298cffbdafe92803ba6566dfa9.deob.ps1
SampleId: `858c6f298cffbdafe92803ba6566dfa9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`79`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 863fd0d0543b6556a236f765d3d94ea2.deob.ps1
SampleId: `863fd0d0543b6556a236f765d3d94ea2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5340`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## 86645790fe4551c096985cab22d439dc.deob.ps1
SampleId: `86645790fe4551c096985cab22d439dc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`44`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 871a7f2b54db8ec6b7f7ccf770cbed5e.deob.ps1
SampleId: `871a7f2b54db8ec6b7f7ccf770cbed5e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`5020`  eligible=`True`  noise=`4983`
Actions: normalized=`37`  effective=`37`  actionNoise=`43`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1406`  byteArrays=`0`  astNodes=`1046`  obf=`21`  clarity=`79`
Stubbed: raw=`13`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- get-itemproperty
- test-path
- new-object
- new-object
- test-path
- test-path
- test-path
- test-path
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- new-object
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 88294dd18a008617f5aa4223f8ff0847.deob.ps1
SampleId: `88294dd18a008617f5aa4223f8ff0847`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`151`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## 885ba03a51de2c40e7508553b87b71dc.deob.ps1
SampleId: `885ba03a51de2c40e7508553b87b71dc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`38`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 8b818bb41e01004eb523f44de6704c5a.deob.ps1
SampleId: `8b818bb41e01004eb523f44de6704c5a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`122`  eligible=`True`  noise=`120`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`72`  byteArrays=`0`  astNodes=`26`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-counter
- foreach-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 8ca6c00422a0f18945525c93bd338b05.deob.ps1
SampleId: `8ca6c00422a0f18945525c93bd338b05`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`211`  eligible=`True`  noise=`208`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`136`  byteArrays=`0`  astNodes=`49`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 8cecd953ff5ee676117e418b5919bff1.deob.ps1
SampleId: `8cecd953ff5ee676117e418b5919bff1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`5044`  eligible=`True`  noise=`5007`
Actions: normalized=`37`  effective=`37`  actionNoise=`43`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1380`  byteArrays=`0`  astNodes=`1062`  obf=`21`  clarity=`79`
Stubbed: raw=`13`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- get-itemproperty
- test-path
- new-object
- new-object
- test-path
- test-path
- test-path
- test-path
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- new-object
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 8d9af2feb075d4d4ee33e30b762fd653.deob.ps1
SampleId: `8d9af2feb075d4d4ee33e30b762fd653`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`98`  eligible=`True`  noise=`98`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`138`  byteArrays=`0`  astNodes=`31`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 8e49c5f522b5b8625b8bb9905063f166.deob.ps1
SampleId: `8e49c5f522b5b8625b8bb9905063f166`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`5020`  eligible=`True`  noise=`4983`
Actions: normalized=`37`  effective=`37`  actionNoise=`43`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`1455`  byteArrays=`0`  astNodes=`1046`  obf=`21`  clarity=`79`
Stubbed: raw=`13`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, start-sleep, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- get-itemproperty
- test-path
- new-object
- new-object
- test-path
- test-path
- test-path
- test-path
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- get-content
- new-object
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## 8eefaf7d971924108a69689b962d4743.deob.ps1
SampleId: `8eefaf7d971924108a69689b962d4743`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`85`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 8f6ced885ecb3ae5a0946d264b178dc9.deob.ps1
SampleId: `8f6ced885ecb3ae5a0946d264b178dc9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`378`  eligible=`True`  noise=`377`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`282`  byteArrays=`0`  astNodes=`157`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- convertto-json
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 912e76f8e61afd80f52436f96640134a.deob.ps1
SampleId: `912e76f8e61afd80f52436f96640134a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`141`  eligible=`True`  noise=`140`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`243`  byteArrays=`0`  astNodes=`38`  obf=`26`  clarity=`74`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 9211de2ffb95441dfcca39296eec1e68.deob.ps1
SampleId: `9211de2ffb95441dfcca39296eec1e68`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`81`  eligible=`True`  noise=`81`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`90`  byteArrays=`0`  astNodes=`19`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## 92fca8f6fa0845090ff2f2040787b45b.deob.ps1
SampleId: `92fca8f6fa0845090ff2f2040787b45b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`122`  eligible=`True`  noise=`120`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`73`  byteArrays=`0`  astNodes=`26`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-counter
- foreach-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 937f7b52c376da87bb66d46ccadde441.deob.ps1
SampleId: `937f7b52c376da87bb66d46ccadde441`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`38`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 95584abd5fead38cc2139bf4b399015d.deob.ps1
SampleId: `95584abd5fead38cc2139bf4b399015d`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`80`  eligible=`True`  noise=`79`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`68`  byteArrays=`0`  astNodes=`35`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-childitem
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 9565655ae773c13eb67d8c889f7aca65.deob.ps1
SampleId: `9565655ae773c13eb67d8c889f7aca65`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`163`  eligible=`True`  noise=`162`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`4`  effective=`4`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`1`  compile=`2`  strings=`12148`  byteArrays=`0`  astNodes=`45`  obf=`38`  clarity=`62`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- powershell.exe
Recorded important API sequence:
- powershell.exe
Effective important API sequence:
- powershell.exe
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- CompileCSharp
- ScriptExec

## 95e28031b0e2f72d05615450ad3a6331.deob.ps1
SampleId: `95e28031b0e2f72d05615450ad3a6331`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`291`  eligible=`True`  noise=`287`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`247`  byteArrays=`0`  astNodes=`87`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadData
- System.Security.Cryptography.MD5.Create
- foreach-object
Recorded important API sequence:
- System.Net.WebClient.DownloadData
Effective important API sequence:
- System.Net.WebClient.DownloadData
Effective capability sequence:
- Download
- ScriptExec

## 95f2745b88bf871f68d7385321a24b4c.deob.ps1
SampleId: `95f2745b88bf871f68d7385321a24b4c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`364`  eligible=`True`  noise=`360`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`374`  byteArrays=`0`  astNodes=`143`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## 96479c119cb5503532f290be4f81e7ec.deob.ps1
SampleId: `96479c119cb5503532f290be4f81e7ec`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `unsafe_timeout`
Instructions: source=`instruction_list`  count=`2229`  eligible=`False`  noise=`2221`
Actions: normalized=`8`  effective=`8`  actionNoise=`1`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`586`  byteArrays=`0`  astNodes=`492`  obf=`12`  clarity=`88`
Stubbed: raw=`2`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.Start, start-sleep
Effective action sequence:
- new-object
- System.Management.Automation.PSObject.Connect
- System.Management.Automation.PSObject.GetStream
- new-object
- new-object
- System.Diagnostics.Process.Start
- new-object
- System.Management.Automation.PSObject.GetBytes
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn

## 968844ee13a010cb396dc616b9a0217d.deob.ps1
SampleId: `968844ee13a010cb396dc616b9a0217d`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`75`  eligible=`True`  noise=`75`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`17`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ScriptExec

## 96ad7508302206d37e6416afe87f6224.deob.ps1
SampleId: `96ad7508302206d37e6416afe87f6224`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 97679d870dc2c0eceaa496ba811aae91.deob.ps1
SampleId: `97679d870dc2c0eceaa496ba811aae91`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`68`  eligible=`True`  noise=`67`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`65`  byteArrays=`0`  astNodes=`25`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 97f39a6a00db23143187dad1c4c2f3b9.deob.ps1
SampleId: `97f39a6a00db23143187dad1c4c2f3b9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 98afdb116f852d7cb718951216286576.deob.ps1
SampleId: `98afdb116f852d7cb718951216286576`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`60`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 98c6d5ff7603142f49eac4306c82ddaa.deob.ps1
SampleId: `98c6d5ff7603142f49eac4306c82ddaa`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2249`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## 99b7611e5179aaa94c7c2a1f8e67e4f4.deob.ps1
SampleId: `99b7611e5179aaa94c7c2a1f8e67e4f4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`84`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## 9a3881d00a75a519099a41def89cbf0f.deob.ps1
SampleId: `9a3881d00a75a519099a41def89cbf0f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`62`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 9b1334943da5c4b19b72ce3297111926.deob.ps1
SampleId: `9b1334943da5c4b19b72ce3297111926`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`20`  byteArrays=`0`  astNodes=`21`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- System.Reflection.Assembly.Load
Recorded important API sequence:
- System.Reflection.Assembly.Load
Effective important API sequence:
- System.Reflection.Assembly.Load
Effective capability sequence: _(none)_

## 9b90ad866bfea7a40b481bb37a9ca634.deob.ps1
SampleId: `9b90ad866bfea7a40b481bb37a9ca634`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`106`  eligible=`True`  noise=`105`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`1`  strings=`1711`  byteArrays=`0`  astNodes=`33`  obf=`11`  clarity=`89`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- add-type
Recorded important API sequence:
- add-type
Effective important API sequence:
- add-type
Effective capability sequence:
- CompileCSharp

## 9c475f377ae2a2614b6fde16d3a81c24.deob.ps1
SampleId: `9c475f377ae2a2614b6fde16d3a81c24`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`46`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 9cbc0386e7d540b0c186ee6a8cb38e99.deob.ps1
SampleId: `9cbc0386e7d540b0c186ee6a8cb38e99`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`64`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 9d7f826626b6618e85c59a4f9faeb758.deob.ps1
SampleId: `9d7f826626b6618e85c59a4f9faeb758`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`99`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## 9efd67c201e3da4e25d2261040d12836.deob.ps1
SampleId: `9efd67c201e3da4e25d2261040d12836`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## 9f3f1491fcff92ab986b1c9781dfe69b.deob.ps1
SampleId: `9f3f1491fcff92ab986b1c9781dfe69b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`207`  eligible=`True`  noise=`204`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`167`  byteArrays=`0`  astNodes=`38`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## a0008befc45056eb88401933e6e61b43.deob.ps1
SampleId: `a0008befc45056eb88401933e6e61b43`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2249`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## a09b94e47807b124accbea3b222cf461.deob.ps1
SampleId: `a09b94e47807b124accbea3b222cf461`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2233`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## a151ff1ba061c0afb0e5dc4399313b87.deob.ps1
SampleId: `a151ff1ba061c0afb0e5dc4399313b87`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`264`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`218`  byteArrays=`0`  astNodes=`74`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## a23c97721b9cd2d427f7af9bbdcd3f55.deob.ps1
SampleId: `a23c97721b9cd2d427f7af9bbdcd3f55`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`97`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`169`  byteArrays=`0`  astNodes=`30`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## a486af36de69b516792c906356f5f7ca.deob.ps1
SampleId: `a486af36de69b516792c906356f5f7ca`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`66`  eligible=`True`  noise=`65`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`58`  byteArrays=`0`  astNodes=`31`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- stop-process
Recorded important API sequence:
- stop-process
Effective important API sequence:
- stop-process
Effective capability sequence: _(none)_

## a4bac9206b52caec6f0c709a1ab3344f.deob.ps1
SampleId: `a4bac9206b52caec6f0c709a1ab3344f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`156`  eligible=`True`  noise=`152`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`283`  byteArrays=`0`  astNodes=`58`  obf=`18`  clarity=`82`
Stubbed: raw=`3`  normalized=`3`  important=`3`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe, System.Management.Automation.PSObject.DownloadFile, cmd.exe
Effective action sequence:
- cmd.exe
- new-object
- System.Net.WebClient.DownloadFile
- cmd.exe
Recorded important API sequence:
- cmd.exe
- System.Net.WebClient.DownloadFile
- cmd.exe
Effective important API sequence:
- cmd.exe
- System.Net.WebClient.DownloadFile
- cmd.exe
Effective capability sequence:
- Download

## a547fd012e2b08854b7e5a8d0cce89e0.deob.ps1
SampleId: `a547fd012e2b08854b7e5a8d0cce89e0`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`151`  eligible=`True`  noise=`148`
Actions: normalized=`2`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`101`  byteArrays=`0`  astNodes=`28`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`fallback_appended`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- invoke-expression
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadString
Effective capability sequence:
- ScriptExec

## a6d1cfeaf74b715130806c390a60815b.deob.ps1
SampleId: `a6d1cfeaf74b715130806c390a60815b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`591`  eligible=`True`  noise=`571`
Actions: normalized=`20`  effective=`20`  actionNoise=`0`
Important APIs: recorded=`7`  effective=`7`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`915`  byteArrays=`0`  astNodes=`138`  obf=`20`  clarity=`80`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- set-alias
- LOPS
- System.String.Replace
- System.String.Replace
- System.String.Replace
- System.String.Replace
- invoke-expression
- new-object
- System.String.Replace
- System.String.Replace
- System.String.Replace
- System.Net.WebClient.DownloadFile
- System.String.Replace
- invoke-expression
- LOPS
- invoke-expression
- new-object
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Recorded important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Effective important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- invoke-expression
- System.Net.WebClient.DownloadFile
- invoke-expression
- remove-item
Effective capability sequence:
- ScriptExec
- Download

## a7587481a4123b7ef8e29fb18f74cf7f.deob.ps1
SampleId: `a7587481a4123b7ef8e29fb18f74cf7f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`48`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## a79c8efacb3f9bd0ca472c5a19497f5e.deob.ps1
SampleId: `a79c8efacb3f9bd0ca472c5a19497f5e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`474`  eligible=`True`  noise=`472`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`338`  byteArrays=`0`  astNodes=`161`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- new-object
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## ac02aa6d569ec5f77215d73b77af7c6c.deob.ps1
SampleId: `ac02aa6d569ec5f77215d73b77af7c6c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2261`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## ad4126ed706cd86b549584790bfe0816.deob.ps1
SampleId: `ad4126ed706cd86b549584790bfe0816`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`62`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## af1fc3379bf48f82a181de007c471cb1.deob.ps1
SampleId: `af1fc3379bf48f82a181de007c471cb1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`34`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## b0540663400ddc6faf3cbb4e2f3ee68c.deob.ps1
SampleId: `b0540663400ddc6faf3cbb4e2f3ee68c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2649`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## b06082bb9568be7e18d648413a78b8fe.deob.ps1
SampleId: `b06082bb9568be7e18d648413a78b8fe`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`47`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## b06f0f5830c7479fa6f1c43b99870684.deob.ps1
SampleId: `b06f0f5830c7479fa6f1c43b99870684`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`910`  eligible=`True`  noise=`902`
Actions: normalized=`8`  effective=`8`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`551`  byteArrays=`0`  astNodes=`223`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- analitycal_data
- System.Text.ASCIIEncoding+ASCIIEncodingSealed.GetBytes
- System.Convert.FromBase64String
- foreach-object
- foreach-object
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## b074e7396747a54b4b328f3b5848b48b.deob.ps1
SampleId: `b074e7396747a54b4b328f3b5848b48b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`504`  eligible=`True`  noise=`501`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`3`  effective=`4`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`1`  strings=`773`  byteArrays=`0`  astNodes=`321`  obf=`10`  clarity=`90`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
Effective capability sequence:
- Download
- RemoteMemoryAlloc
- RemoteThreadCreate
- CompileCSharp

## b1b23ac6f394c3d8c4a862d4b7d69683.deob.ps1
SampleId: `b1b23ac6f394c3d8c4a862d4b7d69683`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`141`  byteArrays=`0`  astNodes=`26`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## b220ed3ba7ced6685be21073fb86173a.deob.ps1
SampleId: `b220ed3ba7ced6685be21073fb86173a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`186`  eligible=`True`  noise=`185`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`61`  byteArrays=`0`  astNodes=`18`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- invoke-expression
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
Effective capability sequence:
- ScriptExec

## b30ef9b708eb98835b5b1b88f199e8b9.deob.ps1
SampleId: `b30ef9b708eb98835b5b1b88f199e8b9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## b3162d06d2708e9ba08c7a36038b92ef.deob.ps1
SampleId: `b3162d06d2708e9ba08c7a36038b92ef`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2225`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## b32b7e12e23aa6deb79b02009cbeccec.deob.ps1
SampleId: `b32b7e12e23aa6deb79b02009cbeccec`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`196`  eligible=`True`  noise=`191`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`5`  effective=`5`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`313`  byteArrays=`0`  astNodes=`119`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Recorded important API sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Effective important API sequence:
- schtasks.exe
- schtasks.exe
- schtasks.exe
- schtasks.exe
- remove-item
Effective capability sequence: _(none)_

## b32e3cc0119189882cef77fc2a2f7fe5.deob.ps1
SampleId: `b32e3cc0119189882cef77fc2a2f7fe5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`145`  eligible=`True`  noise=`143`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`244`  byteArrays=`0`  astNodes=`41`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## b41a8317d5d567d9b21af614941f343f.deob.ps1
SampleId: `b41a8317d5d567d9b21af614941f343f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`38`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## b4af8212a2b2472c7e7493ebcd3be4a7.deob.ps1
SampleId: `b4af8212a2b2472c7e7493ebcd3be4a7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## b4d582c00a864db0825cdf3ee686d066.deob.ps1
SampleId: `b4d582c00a864db0825cdf3ee686d066`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`257`  eligible=`True`  noise=`252`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`354`  byteArrays=`0`  astNodes=`68`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile, System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebRequest.GetSystemWebProxy
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadFile
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec
- ProcessSpawn

## b4f4da39c23a12554c28ee15548352dd.deob.ps1
SampleId: `b4f4da39c23a12554c28ee15548352dd`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`41`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## b5078c61c3dfe0b539802cffd1269ceb.deob.ps1
SampleId: `b5078c61c3dfe0b539802cffd1269ceb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2245`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## b5e619ae93337eaa9de47ac70988c0df.deob.ps1
SampleId: `b5e619ae93337eaa9de47ac70988c0df`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`131`  eligible=`True`  noise=`129`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`95`  byteArrays=`0`  astNodes=`20`  obf=`12`  clarity=`88`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest, powershell.exe
Effective action sequence:
- invoke-webrequest
- powershell.exe
Recorded important API sequence:
- invoke-webrequest
- powershell.exe
Effective important API sequence:
- invoke-webrequest
- powershell.exe
Effective capability sequence:
- Download

## b6f63535b0bee1f3993dc298b17fadae.deob.ps1
SampleId: `b6f63535b0bee1f3993dc298b17fadae`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`66`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## b7f62a1adcb29f97bb1b9f51627236a0.deob.ps1
SampleId: `b7f62a1adcb29f97bb1b9f51627236a0`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`564`  eligible=`True`  noise=`558`
Actions: normalized=`6`  effective=`6`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`875`  byteArrays=`0`  astNodes=`170`  obf=`20`  clarity=`80`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- test-path
- get-childitem
- System.IO.Directory.SetCurrentDirectory
- new-object
- System.Convert.FromBase64CharArray
- invoke-expression
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
Effective capability sequence:
- ScriptExec

## b8463efb009b8f6e408e7c68e6716b48.deob.ps1
SampleId: `b8463efb009b8f6e408e7c68e6716b48`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`569`  eligible=`True`  noise=`563`
Actions: normalized=`6`  effective=`6`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`756`  byteArrays=`0`  astNodes=`165`  obf=`20`  clarity=`80`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- test-path
- get-childitem
- System.IO.Directory.SetCurrentDirectory
- new-object
- System.Convert.FromBase64CharArray
- invoke-expression
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
Effective capability sequence:
- ScriptExec

## b921a84d3586bd3d8dc5d9aefac9ad51.deob.ps1
SampleId: `b921a84d3586bd3d8dc5d9aefac9ad51`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`613`  eligible=`True`  noise=`607`
Actions: normalized=`6`  effective=`6`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`239`  byteArrays=`0`  astNodes=`40`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- start-process
- start-bitstransfer
Recorded important API sequence:
- add-type
- start-process
Effective important API sequence:
- add-type
- start-process
Effective capability sequence:
- CompileCSharp
- ProcessSpawn

## b97ece05fb515b11fc18878197b368c2.deob.ps1
SampleId: `b97ece05fb515b11fc18878197b368c2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`894`  eligible=`True`  noise=`891`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`357`  byteArrays=`0`  astNodes=`125`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- new-item
- out-null
- remove-item
Recorded important API sequence:
- new-item
- remove-item
Effective important API sequence:
- new-item
- remove-item
Effective capability sequence: _(none)_

## ba7d467998b22db262572ec4097e79e4.deob.ps1
SampleId: `ba7d467998b22db262572ec4097e79e4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`85`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## bb408f6288017b9bfd314ec515fc7cc3.deob.ps1
SampleId: `bb408f6288017b9bfd314ec515fc7cc3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`45`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## bbe133be6edd21cb8adcc405f8633221.deob.ps1
SampleId: `bbe133be6edd21cb8adcc405f8633221`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`23`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## bc37b763a94860e6ce3eee04a1742abc.deob.ps1
SampleId: `bc37b763a94860e6ce3eee04a1742abc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`2748`  eligible=`True`  noise=`2726`
Actions: normalized=`22`  effective=`22`  actionNoise=`31`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`1726`  byteArrays=`0`  astNodes=`213`  obf=`7`  clarity=`93`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
- new-object
- System.Management.Automation.PSObject.Add
- System.Management.Automation.PSObject.Add
- System.Management.Automation.PSObject.Add
- new-object
- System.Net.WebClient.UploadValues
Recorded important API sequence:
- System.Net.WebClient.UploadValues
Effective important API sequence:
- System.Net.WebClient.UploadValues
Effective capability sequence: _(none)_

## bd22796110c645b468d932732222d8c7.deob.ps1
SampleId: `bd22796110c645b468d932732222d8c7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`561`  eligible=`True`  noise=`559`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`684`  byteArrays=`0`  astNodes=`345`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- new-object
- schtasks.exe
Recorded important API sequence:
- schtasks.exe
Effective important API sequence:
- schtasks.exe
Effective capability sequence: _(none)_

## be9ab8e5f3896a8d43f9cf4d3f8256c3.deob.ps1
SampleId: `be9ab8e5f3896a8d43f9cf4d3f8256c3`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`95`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`155`  byteArrays=`0`  astNodes=`28`  obf=`24`  clarity=`76`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: curl.exe
Effective action sequence:
- curl.exe
- invoke-item
Recorded important API sequence:
- curl.exe
- invoke-item
Effective important API sequence:
- curl.exe
- invoke-item
Effective capability sequence:
- Download

## bffe02a3de2e218f03d2fe68541543a4.deob.ps1
SampleId: `bffe02a3de2e218f03d2fe68541543a4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`316`  eligible=`True`  noise=`316`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`297`  byteArrays=`0`  astNodes=`139`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## c0307f2ccf20b1642a702bdc26364d6f.deob.ps1
SampleId: `c0307f2ccf20b1642a702bdc26364d6f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`146`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## c09220e548a82a0ef46ad3c26d3a6834.deob.ps1
SampleId: `c09220e548a82a0ef46ad3c26d3a6834`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`4960`  byteArrays=`0`  astNodes=`80`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## c1eb8943ba640dfc83f0b5b81f0fd2fa.deob.ps1
SampleId: `c1eb8943ba640dfc83f0b5b81f0fd2fa`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## c39ae16132530a3c5ae2b19ffb05a3b5.deob.ps1
SampleId: `c39ae16132530a3c5ae2b19ffb05a3b5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`35`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## c42ff572fbe718aa226dd5a9fbc373f1.deob.ps1
SampleId: `c42ff572fbe718aa226dd5a9fbc373f1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`135`  eligible=`True`  noise=`133`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`147`  byteArrays=`0`  astNodes=`36`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## c45866f23ea48e53853e2fd45813a2af.deob.ps1
SampleId: `c45866f23ea48e53853e2fd45813a2af`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`98`  eligible=`True`  noise=`98`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`148`  byteArrays=`0`  astNodes=`31`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## c50ff82b28ff5bced2351de3d256cf55.deob.ps1
SampleId: `c50ff82b28ff5bced2351de3d256cf55`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`151`  eligible=`True`  noise=`148`
Actions: normalized=`2`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`101`  byteArrays=`0`  astNodes=`28`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`fallback_appended`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- invoke-expression
- System.Net.WebClient.DownloadString
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
- System.Net.WebClient.DownloadString
Effective capability sequence:
- ScriptExec

## c615fd8f86d2699e24ca07d86252dd86.deob.ps1
SampleId: `c615fd8f86d2699e24ca07d86252dd86`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`60`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## c6c225d33ea8f6c051f06d2a21c630fb.deob.ps1
SampleId: `c6c225d33ea8f6c051f06d2a21c630fb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2225`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## c792550ae437d915cbbad08bf565fa57.deob.ps1
SampleId: `c792550ae437d915cbbad08bf565fa57`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5336`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## c7deca08f19a9e38448d587361444bc9.deob.ps1
SampleId: `c7deca08f19a9e38448d587361444bc9`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`291`  eligible=`True`  noise=`287`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`246`  byteArrays=`0`  astNodes=`87`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadData
- System.Security.Cryptography.MD5.Create
- foreach-object
Recorded important API sequence:
- System.Net.WebClient.DownloadData
Effective important API sequence:
- System.Net.WebClient.DownloadData
Effective capability sequence:
- Download
- ScriptExec

## c90402515922854c533f101126f1da06.deob.ps1
SampleId: `c90402515922854c533f101126f1da06`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`42`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## ca7725223ab9169a00c62ce49edf0f66.deob.ps1
SampleId: `ca7725223ab9169a00c62ce49edf0f66`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`94`  eligible=`True`  noise=`93`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`821`  byteArrays=`0`  astNodes=`34`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## cb07de1a13d05405c2be4252f986d778.deob.ps1
SampleId: `cb07de1a13d05405c2be4252f986d778`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`93`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## cb7a17827862d8f04eb89d6328d10e12.deob.ps1
SampleId: `cb7a17827862d8f04eb89d6328d10e12`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2205`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## cc2cc10f778ed60d8c086f8b34136b75.deob.ps1
SampleId: `cc2cc10f778ed60d8c086f8b34136b75`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`53`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## ccbe24fe55c81109337d28f3dbcb8a3f.deob.ps1
SampleId: `ccbe24fe55c81109337d28f3dbcb8a3f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`449`  eligible=`True`  noise=`446`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`275`  byteArrays=`0`  astNodes=`125`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-childitem
- new-object
- System.Runtime.InteropServices.Marshal.ReleaseComObject
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## cdc3a96e5521387dd62f7f7eb2bf0363.deob.ps1
SampleId: `cdc3a96e5521387dd62f7f7eb2bf0363`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`89`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## cdf1d542d5cf4ef33d38419387b3a5d7.deob.ps1
SampleId: `cdf1d542d5cf4ef33d38419387b3a5d7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5260`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## cf7591b2286774987359fe2813eb0461.deob.ps1
SampleId: `cf7591b2286774987359fe2813eb0461`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`97`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`165`  byteArrays=`0`  astNodes=`30`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## cfa7b1d9b061d225271645bfdc34ed6d.deob.ps1
SampleId: `cfa7b1d9b061d225271645bfdc34ed6d`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`97`  eligible=`True`  noise=`95`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`1`  launchers=`3`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`147`  byteArrays=`0`  astNodes=`28`  obf=`30`  clarity=`70`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
- invoke-item
Recorded important API sequence:
- invoke-webrequest
- invoke-item
Effective important API sequence:
- invoke-webrequest
- invoke-item
Effective capability sequence:
- Download

## d0a3d42ff36aa154e25a6e0d8890811c.deob.ps1
SampleId: `d0a3d42ff36aa154e25a6e0d8890811c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`21`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## d176f6015a0b9ff678884b0195733cd5.deob.ps1
SampleId: `d176f6015a0b9ff678884b0195733cd5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`46`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## d1fb0d9e98191670b0532ca4d5ad9840.deob.ps1
SampleId: `d1fb0d9e98191670b0532ca4d5ad9840`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`63`  eligible=`True`  noise=`63`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`71`  byteArrays=`0`  astNodes=`10`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## d207c96cff31437d5d09bca3386638bc.deob.ps1
SampleId: `d207c96cff31437d5d09bca3386638bc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`360`  eligible=`True`  noise=`360`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`432`  byteArrays=`0`  astNodes=`200`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## d2b588c682a771d3a2400ba1729ea4fc.deob.ps1
SampleId: `d2b588c682a771d3a2400ba1729ea4fc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`143`  eligible=`True`  noise=`142`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`115`  byteArrays=`0`  astNodes=`15`  obf=`12`  clarity=`88`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- powershell.exe
Recorded important API sequence:
- powershell.exe
Effective important API sequence:
- powershell.exe
Effective capability sequence:
- ProcessSpawn

## d605f7d5392916b976a1f21d38b5b7d1.deob.ps1
SampleId: `d605f7d5392916b976a1f21d38b5b7d1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`45`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## d651c3873db72184fe26ad13fc387e34.deob.ps1
SampleId: `d651c3873db72184fe26ad13fc387e34`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`60`  eligible=`True`  noise=`60`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`60`  byteArrays=`0`  astNodes=`8`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## d65a18cfc601801759711997aac3e3eb.deob.ps1
SampleId: `d65a18cfc601801759711997aac3e3eb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`83`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## d7bb587c84a90377cd3b3ba377bc449d.deob.ps1
SampleId: `d7bb587c84a90377cd3b3ba377bc449d`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`2578`  eligible=`True`  noise=`2562`
Actions: normalized=`16`  effective=`16`  actionNoise=`31`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`379`  byteArrays=`0`  astNodes=`89`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- System.Management.Automation.CommandInvocationIntrinsics.GetCommand
- Set-PSImplicitRemotingSession
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## d970cf93f2056f06a04f9397ec1f8890.deob.ps1
SampleId: `d970cf93f2056f06a04f9397ec1f8890`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`243`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## dbb8d164ce59c24ee3ee399ccec72126.deob.ps1
SampleId: `dbb8d164ce59c24ee3ee399ccec72126`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`278`  eligible=`True`  noise=`277`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`260`  byteArrays=`0`  astNodes=`84`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- get-childitem
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## dbd6708dc8b3b53d5411dcf1994be5e7.deob.ps1
SampleId: `dbd6708dc8b3b53d5411dcf1994be5e7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`93`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- mshta.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## dc0add8d29c903d17f0865f7a3a79bd7.deob.ps1
SampleId: `dc0add8d29c903d17f0865f7a3a79bd7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## dc4f3137206dfc060b5cfcc85445550c.deob.ps1
SampleId: `dc4f3137206dfc060b5cfcc85445550c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`50`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## dca097f80938d4d637cb7d01d029728c.deob.ps1
SampleId: `dca097f80938d4d637cb7d01d029728c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## dcbdefa775abbbdd33733c6d76802ce4.deob.ps1
SampleId: `dcbdefa775abbbdd33733c6d76802ce4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`142`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## dda0e3a8071821b25e8aea1e5152adcb.deob.ps1
SampleId: `dda0e3a8071821b25e8aea1e5152adcb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`90`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## ddcd791ca5d89fa268de4b5aa7d6413d.deob.ps1
SampleId: `ddcd791ca5d89fa268de4b5aa7d6413d`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`111`  byteArrays=`0`  astNodes=`7`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## de8783bb90206e4970c84fabefe7ee20.deob.ps1
SampleId: `de8783bb90206e4970c84fabefe7ee20`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`29`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## df49e67248e76a91ca6abd8ef0d83580.deob.ps1
SampleId: `df49e67248e76a91ca6abd8ef0d83580`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`39`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## df4de0bd80df13610b8807017f07fc16.deob.ps1
SampleId: `df4de0bd80df13610b8807017f07fc16`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`80`  eligible=`True`  noise=`79`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`635`  byteArrays=`0`  astNodes=`38`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## df4fba0a3470a24654c881c054fc88d4.deob.ps1
SampleId: `df4fba0a3470a24654c881c054fc88d4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`695`  eligible=`True`  noise=`690`
Actions: normalized=`5`  effective=`5`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`260`  byteArrays=`0`  astNodes=`115`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Stubbed sinks: start-sleep, start-sleep
Effective action sequence:
- System.Net.WebRequest.Create
- System.Net.HttpWebRequest.GetResponse
- write-output
- invoke-expression
- write-output
Recorded important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective capability sequence:
- ScriptExec

## dfbc377ba8520f5b7c9823c01d629591.deob.ps1
SampleId: `dfbc377ba8520f5b7c9823c01d629591`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`94`  eligible=`True`  noise=`94`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`170`  byteArrays=`0`  astNodes=`28`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## dfd50e33b04699595839d798305ce865.deob.ps1
SampleId: `dfd50e33b04699595839d798305ce865`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`97`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## e12e0de31dbb7cda0abfcf7628edb7bc.deob.ps1
SampleId: `e12e0de31dbb7cda0abfcf7628edb7bc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`74`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## e2633ef500978fa3d6cd25f22df55e3a.deob.ps1
SampleId: `e2633ef500978fa3d6cd25f22df55e3a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`695`  eligible=`True`  noise=`690`
Actions: normalized=`5`  effective=`5`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`275`  byteArrays=`0`  astNodes=`115`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Stubbed sinks: start-sleep, start-sleep
Effective action sequence:
- System.Net.WebRequest.Create
- System.Net.HttpWebRequest.GetResponse
- write-output
- invoke-expression
- write-output
Recorded important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective capability sequence:
- ScriptExec

## e2a7a6c9305c295aeddaa5a2e4a890bf.deob.ps1
SampleId: `e2a7a6c9305c295aeddaa5a2e4a890bf`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`56`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## e30f4e4cf9b58365adfce94a561f9c2f.deob.ps1
SampleId: `e30f4e4cf9b58365adfce94a561f9c2f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2237`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## e396d39daec048518ef963819552b47b.deob.ps1
SampleId: `e396d39daec048518ef963819552b47b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`55`  eligible=`True`  noise=`55`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`245`  byteArrays=`0`  astNodes=`46`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## e3a4e69a135af5549e99b87186bd8a58.deob.ps1
SampleId: `e3a4e69a135af5549e99b87186bd8a58`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`379`  eligible=`True`  noise=`375`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`412`  byteArrays=`0`  astNodes=`159`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## e419d271fb78366b49d5de6edc9a9843.deob.ps1
SampleId: `e419d271fb78366b49d5de6edc9a9843`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5416`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## e52757a7fac119c994ef03f570962e3c.deob.ps1
SampleId: `e52757a7fac119c994ef03f570962e3c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`68`  eligible=`True`  noise=`67`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`65`  byteArrays=`0`  astNodes=`25`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## e6401857515ecfaa34ba6ceecf35b0c1.deob.ps1
SampleId: `e6401857515ecfaa34ba6ceecf35b0c1`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`54`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## e7961249fe86dc9a3710368f11004945.deob.ps1
SampleId: `e7961249fe86dc9a3710368f11004945`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`352`  eligible=`True`  noise=`348`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`357`  byteArrays=`0`  astNodes=`132`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## e7ca0fe5e92bd88cfd657a040ae66e19.deob.ps1
SampleId: `e7ca0fe5e92bd88cfd657a040ae66e19`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`303`  eligible=`True`  noise=`301`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`80`  byteArrays=`0`  astNodes=`46`  obf=`13`  clarity=`87`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- get-childitem
- invoke-expression
Recorded important API sequence:
- invoke-expression
Effective important API sequence:
- invoke-expression
Effective capability sequence:
- ScriptExec

## ea3388ea5b8be72f31af188419431283.deob.ps1
SampleId: `ea3388ea5b8be72f31af188419431283`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`48`  eligible=`True`  noise=`47`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`8`  byteArrays=`0`  astNodes=`5`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- calc.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## ea694e5107d096a6637712a86b95eb29.deob.ps1
SampleId: `ea694e5107d096a6637712a86b95eb29`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`189`  eligible=`True`  noise=`187`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`146`  byteArrays=`0`  astNodes=`30`  obf=`20`  clarity=`80`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest, invoke-webrequest
Effective action sequence:
- invoke-webrequest
- invoke-webrequest
Recorded important API sequence:
- invoke-webrequest
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
- invoke-webrequest
Effective capability sequence:
- Download
- ScriptExec

## ea75a9645de0ec5bcb3f5ee606c6a630.deob.ps1
SampleId: `ea75a9645de0ec5bcb3f5ee606c6a630`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2229`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## ea801ce81deff489f210bbae04d491a0.deob.ps1
SampleId: `ea801ce81deff489f210bbae04d491a0`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`78`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## ec9bbf983f5e580306627a73fa4ca5dc.deob.ps1
SampleId: `ec9bbf983f5e580306627a73fa4ca5dc`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`24`  byteArrays=`0`  astNodes=`6`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## ed2be61dccda589647a7b567f727b89c.deob.ps1
SampleId: `ed2be61dccda589647a7b567f727b89c`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`367`  eligible=`True`  noise=`363`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`343`  byteArrays=`0`  astNodes=`148`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## edb298257c5acc2b7cafee87001959e3.deob.ps1
SampleId: `edb298257c5acc2b7cafee87001959e3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`104`  eligible=`True`  noise=`103`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`66`  byteArrays=`0`  astNodes=`16`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download
- ScriptExec

## eddf3f7f8943e68ecbbdc51b63561802.deob.ps1
SampleId: `eddf3f7f8943e68ecbbdc51b63561802`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`89`  byteArrays=`0`  astNodes=`7`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## ee722053a0cce8a5c548413b732b8031.deob.ps1
SampleId: `ee722053a0cce8a5c548413b732b8031`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`56`  eligible=`True`  noise=`56`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`43`  byteArrays=`0`  astNodes=`7`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- ProcessSpawn

## eea72bf060a1f00bcdf160bb786a46c7.deob.ps1
SampleId: `eea72bf060a1f00bcdf160bb786a46c7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`87`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## eeb8d3f6a9ba28b17a4b0fd94a2ae9f5.deob.ps1
SampleId: `eeb8d3f6a9ba28b17a4b0fd94a2ae9f5`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`52`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## ef133833b1d819db7d39f40c6bd10f79.deob.ps1
SampleId: `ef133833b1d819db7d39f40c6bd10f79`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`94`  eligible=`True`  noise=`94`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`127`  byteArrays=`0`  astNodes=`28`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## f056abc4ecaa5b3ca518e3ef5a749cbb.deob.ps1
SampleId: `f056abc4ecaa5b3ca518e3ef5a749cbb`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`36`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## f08b6e043044a4207916f4021c4f7341.deob.ps1
SampleId: `f08b6e043044a4207916f4021c4f7341`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2249`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## f17845b06c4ff2894ec646fdea840759.deob.ps1
SampleId: `f17845b06c4ff2894ec646fdea840759`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2245`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## f1f87735d9bce2dcf649c44548ec14a2.deob.ps1
SampleId: `f1f87735d9bce2dcf649c44548ec14a2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`98`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## f2b2675d5ce6602a355ba366497f9c3e.deob.ps1
SampleId: `f2b2675d5ce6602a355ba366497f9c3e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`84`  eligible=`True`  noise=`83`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`3`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`527`  byteArrays=`0`  astNodes=`39`  obf=`26`  clarity=`74`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: cmd.exe
Effective action sequence:
- cmd.exe
Recorded important API sequence:
- cmd.exe
Effective important API sequence:
- cmd.exe
Effective capability sequence: _(none)_

## f37a3633454cfa1715ef40fab87ec9e4.deob.ps1
SampleId: `f37a3633454cfa1715ef40fab87ec9e4`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2305`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## f4e4cb4dd8add96c5401ba1bf618553a.deob.ps1
SampleId: `f4e4cb4dd8add96c5401ba1bf618553a`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`132`  eligible=`True`  noise=`127`
Actions: normalized=`5`  effective=`5`  actionNoise=`0`
Important APIs: recorded=`3`  effective=`3`  state=`nonempty`
Capabilities: dynamic=`2`  static=`2`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`697`  byteArrays=`0`  astNodes=`37`  obf=`12`  clarity=`88`
Stubbed: raw=`2`  normalized=`2`  important=`2`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest, powershell.exe
Effective action sequence:
- set-variable
- invoke-webrequest
- select-object
- out-file
- powershell.exe
Recorded important API sequence:
- invoke-webrequest
- out-file
- powershell.exe
Effective important API sequence:
- invoke-webrequest
- out-file
- powershell.exe
Effective capability sequence:
- Download
- FileWrite

## f5b266a09b29fd97afd42466eb8f2714.deob.ps1
SampleId: `f5b266a09b29fd97afd42466eb8f2714`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`54`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## f66741f557a8c4a2dbbd87fcb5fa3850.deob.ps1
SampleId: `f66741f557a8c4a2dbbd87fcb5fa3850`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`289`  eligible=`True`  noise=`285`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`216`  byteArrays=`0`  astNodes=`82`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- System.Net.WebRequest.GetSystemWebProxy
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## f7f99b2f0e81bd0e4b5590be88695094.deob.ps1
SampleId: `f7f99b2f0e81bd0e4b5590be88695094`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`59`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## f8113723ca8d939e2744fed13ee1fd74.deob.ps1
SampleId: `f8113723ca8d939e2744fed13ee1fd74`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`249`  eligible=`True`  noise=`247`
Actions: normalized=`2`  effective=`2`  actionNoise=`1`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`3`  effective=`3`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`2`  compile=`0`  strings=`5364`  byteArrays=`0`  astNodes=`80`  obf=`25`  clarity=`75`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- System.Convert.FromBase64String
- new-object
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence:
- RemoteMemoryAlloc
- RemoteThreadCreate
- ScriptExec

## f89345c79768727117b14025465f895e.deob.ps1
SampleId: `f89345c79768727117b14025465f895e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`102`  byteArrays=`0`  astNodes=`23`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## f9389296d3f83544b32fad1074800ec6.deob.ps1
SampleId: `f9389296d3f83544b32fad1074800ec6`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`207`  eligible=`True`  noise=`204`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`235`  byteArrays=`0`  astNodes=`38`  obf=`31`  clarity=`69`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## f94b1f0ce04e952c2cce67a0d7acbff3.deob.ps1
SampleId: `f94b1f0ce04e952c2cce67a0d7acbff3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`127`  eligible=`True`  noise=`125`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`105`  byteArrays=`0`  astNodes=`32`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadFile
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadFile
Recorded important API sequence:
- System.Net.WebClient.DownloadFile
Effective important API sequence:
- System.Net.WebClient.DownloadFile
Effective capability sequence:
- Download
- ProcessSpawn

## f96cc10151e748adae68c01a5545d241.deob.ps1
SampleId: `f96cc10151e748adae68c01a5545d241`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`280`  eligible=`True`  noise=`279`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`181`  byteArrays=`0`  astNodes=`88`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- new-item
Recorded important API sequence:
- new-item
Effective important API sequence:
- new-item
Effective capability sequence: _(none)_

## f9d70e60ab6650e11cee483f20c1256e.deob.ps1
SampleId: `f9d70e60ab6650e11cee483f20c1256e`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`52`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`80`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## fa09d276d7cb3ad7e7b92ea0d387aeec.deob.ps1
SampleId: `fa09d276d7cb3ad7e7b92ea0d387aeec`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`52`  eligible=`True`  noise=`51`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`55`  byteArrays=`0`  astNodes=`11`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Effective action sequence:
- start-process
Recorded important API sequence:
- start-process
Effective important API sequence:
- start-process
Effective capability sequence:
- ProcessSpawn

## fa2cfcf8587baf6879275d49e3d8d4a3.deob.ps1
SampleId: `fa2cfcf8587baf6879275d49e3d8d4a3`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`105`  eligible=`True`  noise=`105`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`39`  byteArrays=`0`  astNodes=`28`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## facee15250a6009e8999202f7ec3b5b6.deob.ps1
SampleId: `facee15250a6009e8999202f7ec3b5b6`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe`
Instructions: source=`instruction_list`  count=`355`  eligible=`True`  noise=`355`
Actions: normalized=`0`  effective=`0`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`426`  byteArrays=`0`  astNodes=`198`  obf=`6`  clarity=`94`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence: _(none)_
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## fb1fd20a23a3e1dadca31db555b8659f.deob.ps1
SampleId: `fb1fd20a23a3e1dadca31db555b8659f`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`264`  eligible=`True`  noise=`262`
Actions: normalized=`2`  effective=`2`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`4`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`2241`  byteArrays=`0`  astNodes=`115`  obf=`33`  clarity=`67`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Diagnostics.Process.Start
Effective action sequence:
- new-object
- System.Diagnostics.Process.Start
Recorded important API sequence:
- System.Diagnostics.Process.Start
Effective important API sequence:
- System.Diagnostics.Process.Start
Effective capability sequence:
- ProcessSpawn
- ScriptExec

## fb34d918be5f9a6baf121e71276fe133.deob.ps1
SampleId: `fb34d918be5f9a6baf121e71276fe133`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`1122`  eligible=`True`  noise=`1111`
Actions: normalized=`11`  effective=`11`  actionNoise=`0`
Important APIs: recorded=`5`  effective=`5`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`629`  byteArrays=`0`  astNodes=`389`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- System.Reflection.RuntimeAssembly.GetType
- where-object
- System.Management.Automation.PSObject.GetField
- System.Reflection.RtFieldInfo.SetValue
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
- foreach-object
- foreach-object
- invoke-expression
Recorded important API sequence:
- System.Reflection.RtFieldInfo.SetValue
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
- invoke-expression
Effective important API sequence:
- System.Reflection.RtFieldInfo.SetValue
- System.Net.WebHeaderCollection.Add
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadData
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## fb43ea588dc80e46628182fe3b6eca9b.deob.ps1
SampleId: `fb43ea588dc80e46628182fe3b6eca9b`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`588`  eligible=`True`  noise=`576`
Actions: normalized=`12`  effective=`12`  actionNoise=`5`
Important APIs: recorded=`6`  effective=`6`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`392`  byteArrays=`0`  astNodes=`180`  obf=`13`  clarity=`87`
Stubbed: raw=`10`  normalized=`5`  important=`5`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep, System.Management.Automation.PSObject.DownloadString, start-sleep
Effective action sequence:
- new-object
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
- System.Net.WebClient.DownloadString
- foreach-object
Recorded important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
Effective important API sequence:
- System.Net.WebHeaderCollection.Add
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
- System.Net.WebClient.DownloadString
Effective capability sequence:
- Download
- ScriptExec

## fc6ed4fbace0a892fb6617431f52d8da.deob.ps1
SampleId: `fc6ed4fbace0a892fb6617431f52d8da`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`150`  eligible=`True`  noise=`147`
Actions: normalized=`3`  effective=`3`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`84`  byteArrays=`0`  astNodes=`26`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

## fcf9feb43e98d665edc09316d1edf4c2.deob.ps1
SampleId: `fcf9feb43e98d665edc09316d1edf4c2`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`694`  eligible=`True`  noise=`687`
Actions: normalized=`7`  effective=`7`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`0`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`2`  encoded=`1`  dynExec=`0`  compile=`0`  strings=`298`  byteArrays=`0`  astNodes=`64`  obf=`20`  clarity=`80`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: powershell.exe
Effective action sequence:
- IsCurrentProcessArm64
- add-type
- Process.IsArm64
- join-path
- start-bitstransfer
- get-content
- powershell.exe
Recorded important API sequence:
- add-type
- powershell.exe
Effective important API sequence:
- add-type
- powershell.exe
Effective capability sequence:
- CompileCSharp

## fd6c1f822147f198f47d9c29259405d7.deob.ps1
SampleId: `fd6c1f822147f198f47d9c29259405d7`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`64`  eligible=`True`  noise=`63`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`64`  byteArrays=`0`  astNodes=`19`  obf=`6`  clarity=`94`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: invoke-webrequest
Effective action sequence:
- invoke-webrequest
Recorded important API sequence:
- invoke-webrequest
Effective important API sequence:
- invoke-webrequest
Effective capability sequence:
- Download

## fde2cac273c95159ebfc4c0c2253e513.deob.ps1
SampleId: `fde2cac273c95159ebfc4c0c2253e513`
Mode: `deob -> script`  Normalize: `unwrapped_wrapper (depth 1)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`48`  eligible=`True`  noise=`47`
Actions: normalized=`1`  effective=`1`  actionNoise=`0`
Important APIs: recorded=`0`  effective=`0`  state=`empty`
Capabilities: dynamic=`0`  static=`0`  effective=`0`
Mitigation: wrapperDepth=`1`  launchers=`2`  encoded=`0`  dynExec=`0`  compile=`0`  strings=`30`  byteArrays=`0`  astNodes=`5`  obf=`24`  clarity=`76`
Stubbed: raw=`0`  normalized=`0`  important=`0`  coverage=`complete`
Effective action sequence:
- DeviceCredentialDeployment.exe
Recorded important API sequence: _(none)_
Effective important API sequence: _(none)_
Effective capability sequence: _(none)_

## fe928f1521c1f0fb686224bdb6b010c8.deob.ps1
SampleId: `fe928f1521c1f0fb686224bdb6b010c8`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`291`  eligible=`True`  noise=`287`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`1`  effective=`1`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`233`  byteArrays=`0`  astNodes=`87`  obf=`13`  clarity=`87`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadData
Effective action sequence:
- new-object
- System.Net.WebClient.DownloadData
- System.Security.Cryptography.MD5.Create
- foreach-object
Recorded important API sequence:
- System.Net.WebClient.DownloadData
Effective important API sequence:
- System.Net.WebClient.DownloadData
Effective capability sequence:
- Download
- ScriptExec

## ff35237a4bbb510d6f6dd4c365fe1690.deob.ps1
SampleId: `ff35237a4bbb510d6f6dd4c365fe1690`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `partial_visibility`
Instructions: source=`instruction_list`  count=`695`  eligible=`True`  noise=`690`
Actions: normalized=`5`  effective=`5`  actionNoise=`2`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`1`  static=`1`  effective=`1`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`1`  compile=`0`  strings=`260`  byteArrays=`0`  astNodes=`115`  obf=`13`  clarity=`87`
Stubbed: raw=`2`  normalized=`0`  important=`0`  coverage=`fallback_appended`
Stubbed sinks: start-sleep, start-sleep
Effective action sequence:
- System.Net.WebRequest.Create
- System.Net.HttpWebRequest.GetResponse
- write-output
- invoke-expression
- write-output
Recorded important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective important API sequence:
- System.Net.WebRequest.Create
- invoke-expression
Effective capability sequence:
- ScriptExec

## ffbbaabadaf6c225157f0ba99063acfa.deob.ps1
SampleId: `ffbbaabadaf6c225157f0ba99063acfa`
Mode: `deob -> script`  Normalize: `direct (depth 0)`  Safety: `safe_with_stubbed`
Instructions: source=`instruction_list`  count=`218`  eligible=`True`  noise=`214`
Actions: normalized=`4`  effective=`4`  actionNoise=`0`
Important APIs: recorded=`2`  effective=`2`  state=`nonempty`
Capabilities: dynamic=`2`  static=`1`  effective=`2`
Mitigation: wrapperDepth=`0`  launchers=`1`  encoded=`0`  dynExec=`3`  compile=`0`  strings=`106`  byteArrays=`0`  astNodes=`54`  obf=`27`  clarity=`73`
Stubbed: raw=`1`  normalized=`1`  important=`1`  coverage=`complete_with_stubbed`
Stubbed sinks: System.Management.Automation.PSObject.DownloadString
Effective action sequence:
- set-alias
- new-object
- System.Net.WebClient.DownloadString
- invoke-expression
Recorded important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective important API sequence:
- System.Net.WebClient.DownloadString
- invoke-expression
Effective capability sequence:
- Download
- ScriptExec

