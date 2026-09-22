# RBSK Job Aid — Field Mapping (Phase 0.5)

Source: `reference_materials/rbsk_job_aid/` — 4 photographs of the official **"Screening
and Referral Tool for Children (0-6 years)"**, Ministry of Health & Family Welfare,
Government of India, Rashtriya Bal Swasthya Karyakram (RBSK). Pages are numbered
1–4 in the document's own footer ("Job Aids: Rashtriya Bal Swasthya Karyakram (RBSK)
0-6 years | N"), and all 4 pages were supplied (no gaps in page sequence).

This is the AWC (0–6 years) screening tool only. **No School (6+ years) job aid /
referral card was supplied** — School screening's field list and referral options
in [01_PRD.md](01_PRD.md) FR-6 remain as stated in the original brief, not sourced from
an official document. This is an open item — see
[16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) and
[12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md).

Everything below is transcribed as closely as legible from the photographs. Where text
was unclear or a numbering gap was found, it is marked **REVIEW REQUIRED**.

## 1. Preliminary Particulars (page 1 header)

| Field | Type | Notes |
|---|---|---|
| District/Block | Text | |
| Name of ASHA & Contact no. | Text | |
| ASHA ID | Text | |
| Mobile Health Team ID | Text | |
| Name of AWC | Text | |
| AWC ID | Text | |
| Name of Child | Text | Required |
| Name of Father/Guardian | Text | |
| Name of Mother | Text | |
| Contact no. | Text | |
| MCTS No. (16 digit) | Numeric, fixed 16-digit | boxed digit entry on the form |
| *Age of Child (in months/years) | Numeric + unit | footnote: "Age less than 2 years: completed months only; Age more than 2 years: completed years & months" |
| Gender (M/F) | Single-select | two checkboxes |
| Unique ID (16 digit) | Numeric, fixed 16-digit | boxed digit entry |
| AADHAAR No. | Numeric | present on form — see [12_RISKS_OPEN_QUESTIONS.md](12_RISKS_OPEN_QUESTIONS.md) open question on whether to actually collect this |
| Weight (in kg) | Numeric (decimal) | |
| Height/Length (in cm.) | Numeric (decimal) | |
| Head Circumference (in cm) | Numeric (decimal) | |
| *MUAC (in cm) | Numeric (decimal) | footnote: "only in 6-60 months and whose weight is <-2SD" — i.e. **conditional field**, not always collected |

## 2. Anthropometric Classification (page 1, below particulars)

These are **calculated/selected classification fields**, each with an official,
controlled option list (verbatim from the form — not invented):

| Classification | Options (as printed) |
|---|---|
| Weight for age classification (refer chart in Job Aids) | Normal / <-2SD / <-3SD |
| Weight for length/height classification (refer chart in Job Aids) | Normal / <-2SD / <-3SD |
| Height for age classification (refer chart in Job Aids) | Normal / <-2SD / <-3SD |
| Head Circumference classification (refer chart in Job Aids) | Normal / <-2SD (Microcephaly) / <-3SD / >+2SD (Macrocephaly) |
| MUAC classification (only 6–60 months, weight <-2SD) | Red / Yellow / Green |

Footer footnote (page 1): *"If age<6 months: <-3SD (SUW or severe underweight): refer,
and -2SD to -3SD: MUW. If >60 months use BMI: <-3SD as SAM & -2SD to -3SD as MAM"*.

**These classification bands are exactly as printed on the official form** — this
package does not compute or infer SD cutoffs; the app is expected to let the user
select the classification per the Job Aid's own reference charts (referenced but not
themselves photographed — **REVIEW REQUIRED**: the underlying WHO growth-chart lookup
tables referenced as "refer chart in Job Aids" were not part of the supplied
photographs; if the app is expected to auto-classify from raw weight/height rather than
have the user select the classification manually, those charts must be supplied
separately).

## 3. Section A — Defects at Birth (page 1)

If **YES → Refer**. Each item is a single checkbox (tick if present).

| Code | Finding | Description (as printed) |
|---|---|---|
| A1 | Head | Abnormally large or small in size/shape deformity. Measure, Check, Mark HC |
| A1a | — | <-2SD → Micro(cephaly) |
| A1b | — | >+2SD → Macro(cephaly) |
| A2 | Eyes | Any visible abnormality i.e. white pupil, Squint (important esp. after 3 months), frequent jerky movements, tilting the head when focusing (important esp. after 6 months) |
| A3 | Ear | Any abnormality of shape. *Do not refer if isolated finding* |
| A4 | Lips and Palate | Cleft (one side or both sides) |
| A5 | Difficulty in sucking and swallowing | Including sweating on forehead while trying to suck/breast feed (sign is especially important if infant is less than 6 months) |
| A6 | Neck | Exceptionally short. *Do not refer if isolated finding* |
| A7 | HIP: DDH | In case of a female child born through a breech delivery, or child walking with a limp or asymmetrical thigh and gluteal skin folds |
| A8 | Limbs | Any deformity/club foot |
| A9 | Spine | Neural tube defect |
| A10 | Features Suggestive of Down's Syndrome | (Refer Pictorial) *Refer if more than one sign* |
| A10(a) | Eye | Upward slant of eyes (imaginary line from inner to outer canthus goes below the outer canthus), and/or epicanthic fold |
| A10(b) | Nose | Depressed bridge |
| A10(c) | Ears | Low set ears (imaginary line from inner to outer canthus passes above ear) |
| A10(d) | Palm | Single crease across center of palm (Simian crease) |
| A10(e) | Feet | Wide gap (cleft) between the great toe and first toe |
| A11 | Congenital Heart Disease | Any loud murmur on the chest, or cyanosis on lips or bluish spells, or features of congestive cardiac failure (sweating during feeding, recurrent breathing difficulties, poor weight gain, exercise intolerance, easy fatigability, bilateral pitting edema) |

All Section A items: **field type = boolean checkbox, YES-polarity (checked = refer)**.

## 4. Section B — Deficiency (page 1)

If **YES → Refer**.

| Code | Finding | Description |
|---|---|---|
| B1 | *SAM: Weight for Height/length | Refer if child <-3SD per WHO chart, counsel if <-2SD. If age <6 months use Wt-for-age; if >60 months use BMI |
| B2 | SAM – Oedema | Bilateral pitting oedema. Child may have skin lesions or thinning hair |
| B3 | Severe anemia | Look for severe pallor |
| B4 | Vitamin A Deficiency | Ask for night blindness & look for Bitot's spot |
| B5 | Vitamin D Deficiency | Look for wrist widening/bowing of legs/nodular swelling on the chest |
| B8 | Vitamin B complex Deficiency | Angular stomatitis, cheilosis, magenta/fissured/raw tongue, corneal vascularization, malar & supra-orbital pigmentation |
| B9 | Severe Stunting | Height for age below minus 3SD (severe) / minus 2SD (moderate) from WHO Growth chart median. Starts pre-conception, irreversible after age 2, associated with underdeveloped brain/lasting cognitive/learning consequences |

**REVIEW REQUIRED: B6 and B7 do not appear anywhere in the photographed pages.** The
sequence jumps B5 → B8. Either they exist on a portion of the form not photographed
(possible additional vitamin/mineral deficiencies, e.g. Vitamin C/B1), or the source
document itself skips these numbers. Do not assume what B6/B7 are — confirm with the
Job Aid's issuing authority or supply a clearer/complete photograph before finalizing
the Disease Master gap.

## 5. Section C — Disease (pages 1–2)

If **YES → Refer**. *"These are suspected but not confirmed."*

| Code | Finding | Description |
|---|---|---|
| C1 | Convulsive Disorder | Ask about spells of unconsciousness and fits, including momentary blackouts/loss of contact with real world, with or without sudden falls or jerky contractions |
| C2 | Otitis Media | >3 episodes of ear discharge in last 1 year / look for active discharge from ear |
| C3 | Dental Condition | White/brown areas, cavitation, swollen/bleeding/red gums |
| C4 | Skin Condition | Itching on skin (especially at night) / round or oval scaly patches/pustules in finger webs / any other skin lesion |
| C5 | Reactive airway disease | >3 episodes of increased shortness of breath and difficult breathing/wheezing in past 6 months |

### C7 — Childhood Leprosy / Hansen's Disease (page 2, LOOK/ASK/PERFORM)

| Sub-item | Description | Sub-answer / type |
|---|---|---|
| C7.1 | Single localized/discrete lesion or multiple hypo-pigmented patches predominantly on exposed body parts, not present from birth, not painful, not seasonally variable, not itchy, not shedding scales, not preceded by inflammation/injection, not dark red or completely depigmented. **If yes: tick and refer** | checkbox |
| C7.1.1 | If yes, number of lesions present? | 1 to 5 lesions / >5 lesions (single-select) |
| C7.1.2 | If yes, lesion type? | Linear / Non-linear / Raised / Flat (single-select) |
| C7.2 | Any history of close contact with leprosy-affected person in family/neighborhood | checkbox |
| C7.3 | Perform and check: definite impaired sensation at the hypo-pigmented patch | checkbox |
| C7.4 | Perform and check: loss of sensation at hands/feet on both sides. Neural tube defect and any other neurological problem like cerebral palsy — provided one has ruled out | checkbox |
| C7 (overall) | If anyone positive → refer for Hansen's Disease | derived |

*Differential diagnosis note (not a data field):* atopic dermatitis, Pityriasis Alba,
Pityriasis versicolor, Vitiligo, post-inflammatory hypopigmentation, Morphoea, Nevus
depigmentosus, Hypopigmented mycosis fungoides, Hypomelanosis of Ito, halo nevus, linear
lesion (tuberous sclerosis & incontinentia pigmenti).

### C8 — Childhood Tubercular Disease (page 2, LOOK/ASK/PERFORM)

**C8.1 (screening questions, tick if any yes, then proceed to sub-sections below):**

| Item | Description |
|---|---|
| a | Any cough for ≥10 days |
| b | Documented fever for ≥10 days (after common causes excluded) |
| c | Documented weight loss or failure to gain weight |
| d | History of close contact with TB |
| e | Gradually enlarging painless lymph node ≥1.5cm, or any cold abscess/chronic sinus anywhere on body (BCG adenitis occurs ipsilateral to BCG site and mimics TB lymph node) |
| f | Lack of appetite (differentiate from food fads) / malnutrition not improving with appropriate diet |
| g | Child looks ill/lethargic, not interacting, recent altered behaviour >5 days |
| h | Convulsions (rule out benign febrile seizure) |
| i | Recent-onset spinal deformity (Gibbus) |

**C8.1.1 — history sub-items (a–g):**
a) History of recent (past 2 yr) close TB contact (parents/siblings/relatives/caregivers/neighbors)
b) History of Measles, Varicella, or whooping cough in previous 3 months, or on steroids for last 14 days
c) History of a parent HIV-positive
d) Documented weight loss at any age, or poor weight gain (no gain for 1 month in first 3 months of life; no gain over 3 consecutive months aged 3–12 mo.)
e) Documented fever with/without night sweats ≥10 days after common causes excluded (fever >100°F)
f) Malnutrition not improving with supervised diet
g) Arrest or loss of developmental milestones

**C8.1.2 — neurological sub-items (a–g):** altered consciousness; convulsions (rule out
benign febrile seizure); vomiting without diarrhea ± abdominal distension; neck
stiffness/rigidity; bulging anterior fontanelle (esp. upright, not crying); focal
neurological deficit after 1 month of life; cranial nerve palsy (sudden squint/facial
asymmetry after 1 month of life).

**C8.1.3 — respiratory distress table:** increased respiratory rate*** / presents like
sepsis / cough ≥10 days / difficult-to-treat pneumonia (each a checkbox).

**C8.1.4 — lymph node table:** single discrete node / multiple matted nodes /
non-tender & painless / discharging sinus (each a checkbox); enlarged only when neck
>1.5cm or axilla/inguinal >2cm; check for BCG adenitis.

**C8.1.5:** liver and/or spleen enlarged (isolated enlargement not due to TB).

**Diagnostic logic note (printed on form, not a data field):** *"For C8 to be positive,
at least one symptom must be present from C8.1.; C8.1.2 positive in CNS TB; C8.1.3 in
Pulmonary; C8.1.4 positive in TB lymph node; C8.1.5 disseminated TB (with at least one
or more of above, uncommonly isolated hepatosplenomegaly)."*

Footnotes: benign febrile seizure definition; conventional antibiotics list
(Amoxicillin, Amoxyclav, co-trimoxazole, cephalosporins vs. anti-TB drugs Levofloxacin/
Moxifloxacin/Amikacin/Kanamycin); respiratory rate thresholds (>60/min in first month,
>50/min at 2–12 months).

## 6. Section D — Developmental Delays (pages 3–4)

*"LOOK, ASK & PERFORM, AS PER AGE."* Domain tags: **GM**=Gross Motor, **FM**=Fine
Motor, **V**=Vision, **C**=Cognition, **H**=Hearing, **Sp**=Speech, **S**=Social.

**Polarity note — opposite of Sections A/B/C:** the header for this section reads
*"if NO Refer"*. Each item is phrased "Does the child do X?" and a **NO** answer
triggers referral, not a YES. This is a material UI/logic difference from
Sections A–C and must be implemented as such (not merged into one generic
"checked = refer" pattern).

Age bands and item counts (item text is in the source photos; only counts and domain
tags summarized here to keep this document navigable — full item text should be
re-transcribed carefully into the actual form implementation, not paraphrased from
this summary):

| Age band | Items | Domains covered |
|---|---|---|
| >2mo – <4mo | D1.1–D1.8 | GM, FM, H, S, Sp, V, Sp |
| >4mo – <6mo | D2.1–D2.6 | GM, FM, H, Sp, V, Sp |
| >6mo – <9mo | D3.1–D3.7 | GM, FM, H, Sp, V, S, C+V |
| >9mo – <12mo | D4.1–D4.6 | GM, FM, H&C, Sp, V, S |
| 12mo – <15mo | D5.1–D5.7 | GM, FM, H&C, Sp, S, S&C, C |
| >15mo – <18mo | D6.1–D6.6 | GM, FM, FM, H&C, Sp, C |
| 18mo – <24mo | D7.1–D7.5 | GM, FM, Sp, C, H&C |
| 24mo – <30mo | D8.1–D8.5 | GM, FM, Sp, S, C |

**D9.1:** "Any Neuro-Motor abnormality (refer to picture in Job Aids)" — *if YES refer*
(note: reverts to YES-polarity for this single item).

**D10 — Autism Specific Questionnaire** (*"Answer Y/N discretely"*):

| Age band | Item | Question | Refer trigger |
|---|---|---|---|
| 15–18mo | D10.1.1 | Poor eye contact for >1–2 sec | If N refer |
| 15–18mo | D10.1.2 | Uses index finger to point to ask for something | If N refer |
| 15–18mo | D10.1.3 | Ever wondered child is deaf / not responding to name (not communicating via gestures) | If Y refer |
| 18–24mo | D10.2.1 | Interest in / play with other children | If N refer |
| 18–24mo | D10.2.2 | Unusual finger movements/repetitive hand-body movements (wriggling/flapping/spinning/jumping) — repeated purposeless motor activity | If Y refer |
| 18–24mo | D10.3.3 | Pretend play (phone/dolls) | If N refer |

**REVIEW REQUIRED:** D10.3.1 and D10.3.2 are not visible in the photographs (numbering
jumps from D10.2.2 to D10.3.3) — likely present on a part of the page not clearly
captured. Do not guess their content.

**D11 — Screening tool for age 2.5–6 years** (*"if YES refer"* — reverts to
YES-polarity):

| Item | Question | Domain |
|---|---|---|
| D11.2 | Delay in walking compared to peers | GM |
| D11.3 | Stiffness/floppiness or reduced strength in arms/legs | GM |
| D11.4 | Ever had fits/rigidity/sudden jerks or spasms (Convulsive Disorder) | — |
| D11.5 | Ever lost consciousness (Convulsive Disorder) | — |
| D11.6 | Difficulty reading/writing/simple calculations vs. peers | C |
| D11.7 | Difficulty seeing day/night without spectacles | V |
| D11.8 | Difficulty speaking vs. peers | Sp |
| D11.9 | Speech different from peers | Sp |
| D11.10 | Difficulty hearing without hearing aid | H |
| D11.11 | Difficulty sustaining attention vs. peers | C |
| (D11.12?) | Difficulty learning new things vs. peers | C |

**REVIEW REQUIRED: D11.1 is not visible** (sequence starts at D11.2 in the
photographs) and the last item's number is not clearly legible — confirm exact
numbering against a clean copy of the form.

## 7. Preliminary Findings & Referral — Official Disease/Finding Master (page 4)

This table is the authoritative, codified Disease Master. Codes and category grouping
are transcribed exactly as printed — **this supersedes the placeholder/example
categories in [04_DATABASE_ARCHITECTURE.md](04_DATABASE_ARCHITECTURE.md)** and should
be used to seed `disease_master` (see
[16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md)).

**Defects at Birth**

| Code | Finding |
|---|---|
| 1 | Neural Tube Defect |
| 2 | Down's Syndrome |
| 3 | Cleft Lip & Palate |
| 4 | Talipes (club foot) |
| 5 | Developmental Dysplasia of Hip |
| 6 | Congenital Cataract |
| 7 | Congenital Deafness |
| 8 | Congenital Heart Disease |
| 9 | ROP (only at DH) |
| 42 | Microcephaly |
| 43 | Macrocephaly |

**Deficiencies**

| Code | Finding |
|---|---|
| 10 | Severe Anemia |
| 11 | Vitamin A Def. |
| 12 | Vitamin D Deficiency |
| 13 | SAM up to 60 mon. |
| 14 | Goiter (usually after 6 years) |
| 41 | Severe Stunting |
| 44 | Vitamin B complex def. |
| 30 | Others (Specify) |

**Diseases**

| Code | Finding |
|---|---|
| 15 | Skin Conditions |
| 16 | Otitis Media |
| 17 | Rheumatic Heart Dis. |
| 18 | Bronchial Asthma (Reactive Airway Dis.) |
| 19 | Dental Conditions |
| 20 | Convulsive Disorders |
| 39 | Childhood Leprosy Disease |
| 40 | Childhood T.B. |
| 40.1 | Childhood Extra Pulmonary T.B. |

**Developmental Delay & Disability**

| Code | Finding |
|---|---|
| 21 | Vision Impairment |
| 22 | Hearing Impairment |
| 23 | Neuro-motor Impairment |
| 24 | Motor Delay |
| 25 | Cognitive Delay |
| 26 | Speech and Language Delay |
| 27 | Behavioral Disorder (Autism) |
| 28 | Learning Disorder |
| 29 | Attention Deficit Hyperactivity Disorder |

**REVIEW REQUIRED:** codes 31–38 are not used anywhere in the visible table (sequence
jumps 30 → 39, and 14 → 41). This may simply be how the official form numbers things
(reserved/retired codes), or a section wasn't captured. Do not assume codes 31–38 exist
or what they'd mean.

## 8. Referral Routing (page 4, bottom)

This is the **actual official referral-destination logic**, and it is materially more
specific than the 3-option `PHC_CHC / DISTRICT_HOSPITAL / HIGHER_CENTER` enum carried
in the original Phase 0 database design. Per category:

| Finding category | Official referral destination(s) |
|---|---|
| Defects at Birth | DH / DEIC (District Early Intervention Centre) |
| Deficiency | PHC/CHC; **SAM specifically → NRC** (Nutrition Rehabilitation Centre) |
| Disease | PHC/CHC/DH; **Dental condition specifically → DEIC/DH** |
| Developmental Delay & Disability | DEIC |
| Others | PHC/CHC/DH |

Each category also has its own **Yes/No "Please ✓" and "Referral: Yes/No"** checkboxes
on the form — i.e. the form supports *partial* referral (a child can have a Defects
finding not referred and a Deficiency finding that is, independently).

**Explicit priority rule (printed, not inferred):** *"In case the referral has to be
made for more than 1D [1 domain] especially involving the DEIC, the child must be
referred to DEIC first."*

**Sign-off fields:** Name and Sign of Doctor/MHT · Date of Visit · "Data entered in
Register – Yes/No" · "Data entered in register by Name and Sign".

**Developmental red flags (printed reference note, not a data field):** No head control
by 3 months; fisting beyond 3 months; no two-word phrase or no pointing/pretend play by
24 months; echolalia after 30 months.

See [16_PHASE0_DATABASE_REVIEW.md](16_PHASE0_DATABASE_REVIEW.md) for how this changes
the `referral_destination` enum and the referral-routing logic.

## 9. Items requiring review before Phase 1 build

| Item | Issue |
|---|---|
| B6, B7 | Missing from Deficiency section — confirm content |
| D10.3.1, D10.3.2 | Missing from Autism questionnaire — confirm content |
| D11.1, and D11's last item number | Not clearly visible — confirm exact numbering |
| Codes 31–38 | Unused/missing in Disease Master table — confirm whether reserved or uncaptured |
| WHO growth chart lookup tables | Referenced ("refer chart in Job Aids") but not photographed — needed only if the app is expected to auto-classify anthropometry rather than let the user select the classification |
| School (6+ yrs) screening/referral card | Not supplied at all — School screening fields remain as stated in the original brief, unconfirmed against an official document |
