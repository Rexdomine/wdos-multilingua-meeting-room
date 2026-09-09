/** African countries + Nigerian states — shared by profile & apply forms. */
export const AFRICAN_COUNTRIES = [
  'Algeria', 'Angola', 'Benin', 'Botswana', 'Burkina Faso', 'Burundi',
  'Cabo Verde', 'Cameroon', 'Central African Republic', 'Chad', 'Comoros',
  'Congo (Brazzaville)', 'Congo (DRC)', "Côte d'Ivoire", 'Djibouti',
  'Egypt', 'Equatorial Guinea', 'Eritrea', 'Eswatini', 'Ethiopia', 'Gabon',
  'Gambia', 'Ghana', 'Guinea', 'Guinea-Bissau', 'Kenya', 'Lesotho',
  'Liberia', 'Libya', 'Madagascar', 'Malawi', 'Mali', 'Mauritania',
  'Mauritius', 'Morocco', 'Mozambique', 'Namibia', 'Niger', 'Nigeria',
  'Rwanda', 'São Tomé & Príncipe', 'Senegal', 'Seychelles', 'Sierra Leone',
  'Somalia', 'South Africa', 'South Sudan', 'Sudan', 'Tanzania', 'Togo',
  'Tunisia', 'Uganda', 'Zambia', 'Zimbabwe', 'Other (outside Africa)',
];

export const NG_STATES = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa', 'Benue',
  'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti', 'Enugu',
  'FCT (Abuja)', 'Gombe', 'Imo', 'Jigawa', 'Kaduna', 'Kano', 'Katsina',
  'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger', 'Ogun', 'Ondo',
  'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba', 'Yobe', 'Zamfara',
];

export const COUNTRY_ISO = {
  'Algeria':'DZ','Angola':'AO','Benin':'BJ','Botswana':'BW',
  'Burkina Faso':'BF','Burundi':'BI','Cabo Verde':'CV','Cameroon':'CM',
  'Central African Republic':'CF','Chad':'TD','Comoros':'KM',
  'Congo (Brazzaville)':'CG','Congo':'CG','Congo (DRC)':'CD','DR Congo':'CD',
  "Côte d'Ivoire":'CI','Djibouti':'DJ','Egypt':'EG','Equatorial Guinea':'GQ',
  'Eritrea':'ER','Eswatini':'SZ','Ethiopia':'ET','Gabon':'GA','Gambia':'GM',
  'Ghana':'GH','Guinea':'GN','Guinea-Bissau':'GW','Kenya':'KE','Lesotho':'LS',
  'Liberia':'LR','Libya':'LY','Madagascar':'MG','Malawi':'MW','Mali':'ML',
  'Mauritania':'MR','Mauritius':'MU','Morocco':'MA','Mozambique':'MZ',
  'Namibia':'NA','Niger':'NE','Nigeria':'NG','Rwanda':'RW',
  'São Tomé & Príncipe':'ST','Senegal':'SN','Seychelles':'SC',
  'Sierra Leone':'SL','Somalia':'SO','South Africa':'ZA','South Sudan':'SS',
  'Sudan':'SD','Tanzania':'TZ','Togo':'TG','Tunisia':'TN','Uganda':'UG',
  'Zambia':'ZM','Zimbabwe':'ZW',
};

/* Phase 137 — country flags (bundled SVGs in /assets/flags, works on every device) */
const COUNTRY_ISO_ALIASES = {"Cape Verde": "CV", "Congo": "CG", "Republic of the Congo": "CG", "DR Congo": "CD", "Democratic Republic of the Congo": "CD", "Gambia": "GM", "The Gambia": "GM", "Ivory Coast": "CI", "Cote d'Ivoire": "CI", "Côte d'Ivoire": "CI", "Sao Tome and Principe": "ST", "São Tomé and Príncipe": "ST", "Eswatini": "SZ", "Tanzania": "TZ"};
export function countryIso(name, fallbackIso) {
  if (fallbackIso) return String(fallbackIso).toUpperCase();
  if (!name) return null;
  const all = { ...COUNTRY_ISO, ...COUNTRY_ISO_ALIASES };
  const k = Object.keys(all).find((n) => n.toLowerCase() === String(name).trim().toLowerCase());
  return k ? all[k] : null;
}
export function flagSrc(iso) { return iso ? `/assets/flags/${String(iso).toLowerCase()}.svg` : null; }
