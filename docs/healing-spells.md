# Healing spells

Catalogue date: **5 September 2026**. The supplied implementation plan reports verification against the official Tibia Library on this date. During implementation, all entries were independently checked against TibiaWiki BR, a community reference. Attempts to retrieve the official Restoration and Intense Wound Cleansing entries, release news 8833, and Rule 3b returned HTTP 403, so this implementation run did not independently reproduce the reported official verification.

Vocation families include promotions: Knight / Elite Knight, Paladin / Royal Paladin, Sorcerer / Master Sorcerer, Druid / Elder Druid, Monk / Exalted Monk. [Promotion reference](https://www.tibiawiki.com.br/wiki/Promotion).

## Emergency self-healing

Cooldowns are base values in seconds. Group means the Healing group.

| Spell | Formula | Vocation family | Individual | Group | Cross-check |
|---|---|---|---:|---:|---|
| [Magic Patch](https://www.tibia.com/library/?spell=magicpatch&subtopic=spells) | `exura infir` | Druid, Sorcerer, Paladin, Monk | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Magic_Patch) |
| [Light Healing](https://www.tibia.com/library/?spell=lighthealing&subtopic=spells) | `exura` | Druid, Sorcerer, Paladin, Monk | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Light_Healing) |
| [Intense Healing](https://www.tibia.com/library/?spell=intensehealing&subtopic=spells) | `exura gran` | Druid, Sorcerer, Paladin, Monk | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Intense_Healing) |
| [Ultimate Healing](https://www.tibia.com/library/?spell=ultimatehealing&subtopic=spells) | `exura vita` | Druid, Sorcerer | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Ultimate_Healing) |
| [Restoration](https://www.tibia.com/library/?spell=restoration&subtopic=spells) | `exura max vita` | Druid, Sorcerer | 6 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Restoration) |
| [Divine Healing](https://www.tibia.com/library/?spell=divinehealing&subtopic=spells) | `exura san` | Paladin | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Divine_Healing) |
| [Salvation](https://www.tibia.com/library/?spell=salvation&subtopic=spells) | `exura gran san` | Paladin | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Salvation) |
| [Bruise Bane](https://www.tibia.com/library/?spell=bruisebane&subtopic=spells) | `exura infir ico` | Knight | 2 | 2 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Bruise_Bane) |
| [Wound Cleansing](https://www.tibia.com/library/?spell=woundcleansing&subtopic=spells) | `exura ico` | Knight | 2 | 2 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Wound_Cleansing) |
| [Fair Wound Cleansing](https://www.tibia.com/library/?spell=fairwoundcleansing&subtopic=spells) | `exura med ico` | Knight | 2 | 2 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Fair_Wound_Cleansing) |
| [Intense Wound Cleansing](https://www.tibia.com/library/?spell=intensewoundcleansing&subtopic=spells) | `exura gran ico` | Knight | 120 | 2 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Intense_Wound_Cleansing) |
| [Spirit Mend](https://www.tibia.com/library/?spell=spiritmend&subtopic=spells) | `exura gran tio` | Monk | 1 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Spirit_Mend) |

## Self-regeneration

These spells are reference-only and excluded from Heal / Critical choices.

| Spell | Formula | Vocation family | Individual | Group | Cross-check |
|---|---|---|---:|---:|---|
| [Recovery](https://www.tibia.com/library/?spell=recovery&subtopic=spells) | `utura` | Knight, Paladin | 60 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Recovery) |
| [Intense Recovery](https://www.tibia.com/library/?spell=intenserecovery&subtopic=spells) | `utura gran` | Knight, Paladin | 60 | 1 | [TibiaWiki BR](https://www.tibiawiki.com.br/wiki/Intense_Recovery) |

## Scheduling and configuration

Individual cooldown is tracked by spell identity across both slots. Both individual and Healing-group readiness are checked when reserving input and immediately before key-down. After Restoration, Ultimate Healing can become eligible after 1 second; Restoration itself requires 6 seconds. Failed or cancelled dispatches before key-down consume no cooldown. Successful key-down records a conservative attempt even if the client does not cast, and stopping does not erase that attempt.

Intense Wound Cleansing uses 120 seconds individual and 2 seconds Healing-group cooldown. Older references listing 600 seconds are outdated. The supplied plan identifies [official release news 8833](https://www.tibia.com/news/?id=8833&subtopic=newsarchive) as the official change source.

Vocation selection is optional and saved with configuration and presets. Older configurations initially show all vocations and preserve existing spell selections. Changing vocation or spell cancels queued healing. Incompatible selections remain visible, but cannot cast. No spell is substituted automatically. Critical potion mode does not use the critical spell selector.

The selected spell must match the client hotkey. Selection does not validate learned spells, character level, premium status or mana requirements. No Wheel of Destiny reductions or server-confirmed casting are inferred. Existing threshold confirmations and normal-heal fallback remain in effect.

## Magic Shield and runtime verification

The Active Systems Magic Shield control and Healing settings use the same persisted enable setting. Disabling cancels queued activation. Observed shield capacity remains separate from the enable setting. STOP cancels queued input while preserving the configured toggle.

Manual comparison with the client cooldown display has not been performed. Screen Recording and Accessibility are still required for capture and input; this change adds no permissions. [Tibia Rule 3b](https://www.tibia.com/support/?mobile-app=true&rule=3b&subtopic=tibiarules&theme=false) prohibits using additional software to play automatically and warns that it may lead to punishment.
