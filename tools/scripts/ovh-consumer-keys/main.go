// ovh-consumer-keys génère des consumer keys OVH à partir d'un fichier de
// configuration YAML. Permet de créer un token par domaine (isolation forte)
// ou un token global couvrant plusieurs domaines (simplicité de gestion).
//
// Usage:
//   ovh-consumer-keys -config config.yaml
//   ovh-consumer-keys -config config.yaml -mode per-domain
//   ovh-consumer-keys -config config.yaml -mode all-in-one
//   ovh-consumer-keys -config config.yaml -output results.yaml
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	defaultEndpoint = "https://eu.api.ovh.com/1.0"
	requestTimeout  = 30 * time.Second
)

// --- Types de configuration ---

// Config est la racine du fichier YAML de configuration.
type Config struct {
	// Endpoint OVH ("ovh-eu", "ovh-ca", ...). Optionnel, défaut: ovh-eu.
	Endpoint string `yaml:"endpoint,omitempty"`

	// ApplicationKey est nécessaire pour authentifier la demande de consumer key.
	// Peut être fournie via la variable d'environnement OVH_APPLICATION_KEY
	// pour éviter de la stocker dans le fichier.
	ApplicationKey string `yaml:"application_key,omitempty"`

	// RedirectURL est l'URL vers laquelle OVH renvoie l'utilisateur après
	// validation. Pas critique, peut être laissée vide (OVH affichera une page
	// par défaut).
	RedirectURL string `yaml:"redirect_url,omitempty"`

	// Permissions définit le set de permissions à appliquer à chaque zone.
	// Par défaut: cert-manager DNS-01 (GET/POST/DELETE sur zone et records).
	Permissions []Permission `yaml:"permissions,omitempty"`

	// Domains est la liste des zones DNS à inclure.
	Domains []Domain `yaml:"domains"`
}

// Domain représente une zone DNS chez OVH.
type Domain struct {
	// Name est le nom de la zone (ex: "alter-it.eu").
	Name string `yaml:"name"`

	// Description est optionnelle, pour documenter (ex: "domaine opérateur").
	Description string `yaml:"description,omitempty"`

	// Permissions surchargent celles définies au niveau racine, si fournies.
	Permissions []Permission `yaml:"permissions,omitempty"`
}

// Permission est un couple méthode HTTP + path API OVH.
// Le placeholder {domain} dans Path sera remplacé par le nom de la zone.
type Permission struct {
	Method string `yaml:"method"`
	Path   string `yaml:"path"`
}

// --- Types de la réponse OVH ---

type ovhRule struct {
	Method string `json:"method"`
	Path   string `json:"path"`
}

type ovhCredentialRequest struct {
	AccessRules []ovhRule `json:"accessRules"`
	Redirection string    `json:"redirection,omitempty"`
}

type ovhCredentialResponse struct {
	ValidationURL string `json:"validationUrl"`
	ConsumerKey   string `json:"consumerKey"`
	State         string `json:"state"`
}

type ovhAPIError struct {
	ErrorCode string `json:"errorCode"`
	Message   string `json:"message"`
}

// --- Types de la sortie ---

// Result représente le résultat de la création d'un consumer key.
type Result struct {
	Label         string   `yaml:"label" json:"label"`
	Domains       []string `yaml:"domains" json:"domains"`
	ConsumerKey   string   `yaml:"consumer_key" json:"consumer_key"`
	ValidationURL string   `yaml:"validation_url" json:"validation_url"`
	RulesCount    int      `yaml:"rules_count" json:"rules_count"`
}

// Output regroupe tous les Results pour l'écriture finale.
type Output struct {
	Endpoint    string   `yaml:"endpoint" json:"endpoint"`
	GeneratedAt string   `yaml:"generated_at" json:"generated_at"`
	Results     []Result `yaml:"results" json:"results"`
}

// --- Permissions par défaut (cert-manager DNS-01) ---

func defaultPermissions() []Permission {
	return []Permission{
		{Method: "GET", Path: "/domain/zone/{domain}"},
		{Method: "GET", Path: "/domain/zone/{domain}/record"},
		{Method: "GET", Path: "/domain/zone/{domain}/record/*"},
		{Method: "POST", Path: "/domain/zone/{domain}/record"},
		{Method: "DELETE", Path: "/domain/zone/{domain}/record/*"},
		{Method: "POST", Path: "/domain/zone/{domain}/refresh"},
	}
}

// --- Chargement de la config ---

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse yaml: %w", err)
	}

	// Endpoint par défaut
	if cfg.Endpoint == "" {
		cfg.Endpoint = "ovh-eu"
	}

	// ApplicationKey via env si non fournie dans le YAML
	if cfg.ApplicationKey == "" {
		cfg.ApplicationKey = os.Getenv("OVH_APPLICATION_KEY")
	}
	if cfg.ApplicationKey == "" {
		return nil, fmt.Errorf("application_key non définie (ni dans le YAML ni dans OVH_APPLICATION_KEY)")
	}

	// Permissions par défaut si non fournies au niveau racine
	if len(cfg.Permissions) == 0 {
		cfg.Permissions = defaultPermissions()
	}

	// Validation: il faut au moins un domaine
	if len(cfg.Domains) == 0 {
		return nil, fmt.Errorf("aucun domaine défini dans la configuration")
	}

	return &cfg, nil
}

// --- Construction des rules ---

// buildRulesForDomain prend une liste de permissions et un nom de domaine,
// et retourne les rules OVH avec le placeholder {domain} remplacé.
func buildRulesForDomain(perms []Permission, domain string) []ovhRule {
	rules := make([]ovhRule, 0, len(perms))
	for _, p := range perms {
		rules = append(rules, ovhRule{
			Method: p.Method,
			Path:   strings.ReplaceAll(p.Path, "{domain}", domain),
		})
	}
	return rules
}

// --- Appel API OVH ---

func endpointURL(name string) string {
	switch name {
	case "ovh-eu":
		return "https://eu.api.ovh.com/1.0"
	case "ovh-ca":
		return "https://ca.api.ovh.com/1.0"
	case "ovh-us":
		return "https://api.us.ovhcloud.com/1.0"
	case "kimsufi-eu":
		return "https://eu.api.kimsufi.com/1.0"
	case "kimsufi-ca":
		return "https://ca.api.kimsufi.com/1.0"
	case "soyoustart-eu":
		return "https://eu.api.soyoustart.com/1.0"
	case "soyoustart-ca":
		return "https://ca.api.soyoustart.com/1.0"
	default:
		return defaultEndpoint
	}
}

// requestConsumerKey appelle POST /auth/credential et retourne la réponse.
func requestConsumerKey(endpoint, applicationKey string, rules []ovhRule, redirection string) (*ovhCredentialResponse, error) {
	reqBody := ovhCredentialRequest{
		AccessRules: rules,
		Redirection: redirection,
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	url := endpoint + "/auth/credential"
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Ovh-Application", applicationKey)

	client := &http.Client{Timeout: requestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		var apiErr ovhAPIError
		if err := json.Unmarshal(respBody, &apiErr); err == nil && apiErr.Message != "" {
			return nil, fmt.Errorf("ovh api error (%d %s): %s", resp.StatusCode, apiErr.ErrorCode, apiErr.Message)
		}
		return nil, fmt.Errorf("ovh api error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var result ovhCredentialResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	return &result, nil
}

// --- Stratégies de génération ---

// generatePerDomain crée un consumer key par domaine.
func generatePerDomain(cfg *Config) ([]Result, error) {
	endpoint := endpointURL(cfg.Endpoint)
	results := make([]Result, 0, len(cfg.Domains))

	for _, d := range cfg.Domains {
		perms := d.Permissions
		if len(perms) == 0 {
			perms = cfg.Permissions
		}

		rules := buildRulesForDomain(perms, d.Name)

		fmt.Fprintf(os.Stderr, "→ Génération du consumer key pour %s (%d rules)...\n", d.Name, len(rules))

		resp, err := requestConsumerKey(endpoint, cfg.ApplicationKey, rules, cfg.RedirectURL)
		if err != nil {
			return results, fmt.Errorf("domaine %s: %w", d.Name, err)
		}

		results = append(results, Result{
			Label:         d.Name,
			Domains:       []string{d.Name},
			ConsumerKey:   resp.ConsumerKey,
			ValidationURL: resp.ValidationURL,
			RulesCount:    len(rules),
		})

		fmt.Fprintf(os.Stderr, "  ✓ consumer_key=%s\n", resp.ConsumerKey)
		fmt.Fprintf(os.Stderr, "  ✓ validation_url=%s\n", resp.ValidationURL)
	}

	return results, nil
}

// generateAllInOne crée un seul consumer key couvrant tous les domaines.
func generateAllInOne(cfg *Config) ([]Result, error) {
	endpoint := endpointURL(cfg.Endpoint)

	allRules := make([]ovhRule, 0, len(cfg.Domains)*len(cfg.Permissions))
	domainNames := make([]string, 0, len(cfg.Domains))

	for _, d := range cfg.Domains {
		perms := d.Permissions
		if len(perms) == 0 {
			perms = cfg.Permissions
		}
		allRules = append(allRules, buildRulesForDomain(perms, d.Name)...)
		domainNames = append(domainNames, d.Name)
	}

	fmt.Fprintf(os.Stderr, "→ Génération d'un consumer key unique pour %d domaines (%d rules au total)...\n",
		len(domainNames), len(allRules))

	resp, err := requestConsumerKey(endpoint, cfg.ApplicationKey, allRules, cfg.RedirectURL)
	if err != nil {
		return nil, err
	}

	result := Result{
		Label:         "all-domains",
		Domains:       domainNames,
		ConsumerKey:   resp.ConsumerKey,
		ValidationURL: resp.ValidationURL,
		RulesCount:    len(allRules),
	}

	fmt.Fprintf(os.Stderr, "  ✓ consumer_key=%s\n", resp.ConsumerKey)
	fmt.Fprintf(os.Stderr, "  ✓ validation_url=%s\n", resp.ValidationURL)

	return []Result{result}, nil
}

// --- Écriture de la sortie ---

func writeOutput(out *Output, path, format string) error {
	var data []byte
	var err error

	switch format {
	case "yaml":
		data, err = yaml.Marshal(out)
	case "json":
		data, err = json.MarshalIndent(out, "", "  ")
	default:
		return fmt.Errorf("format inconnu: %s (yaml ou json)", format)
	}

	if err != nil {
		return fmt.Errorf("marshal output: %w", err)
	}

	if path == "-" || path == "" {
		_, err = os.Stdout.Write(data)
		return err
	}

	return os.WriteFile(path, data, 0600)
}

// --- Main ---

func main() {
	var (
		configPath = flag.String("config", "config.yaml", "Chemin du fichier de configuration YAML")
		mode       = flag.String("mode", "per-domain", "Stratégie: per-domain (un token par domaine) ou all-in-one (un seul token pour tous)")
		outputPath = flag.String("output", "-", "Chemin du fichier de sortie ('-' pour stdout)")
		format     = flag.String("format", "yaml", "Format de sortie: yaml ou json")
	)
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Erreur de chargement de la config: %v\n", err)
		os.Exit(1)
	}

	var results []Result
	switch *mode {
	case "per-domain":
		results, err = generatePerDomain(cfg)
	case "all-in-one":
		results, err = generateAllInOne(cfg)
	default:
		fmt.Fprintf(os.Stderr, "Mode inconnu: %s (per-domain ou all-in-one)\n", *mode)
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Erreur lors de la génération: %v\n", err)
		// On essaie quand même d'écrire les résultats partiels obtenus avant l'erreur
		if len(results) > 0 {
			fmt.Fprintln(os.Stderr, "Écriture des résultats partiels...")
		} else {
			os.Exit(1)
		}
	}

	out := &Output{
		Endpoint:    cfg.Endpoint,
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
		Results:     results,
	}

	if err := writeOutput(out, *outputPath, *format); err != nil {
		fmt.Fprintf(os.Stderr, "Erreur d'écriture: %v\n", err)
		os.Exit(1)
	}

	// Récap sur stderr pour le user
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintf(os.Stderr, "═══════════════════════════════════════════════════════════════\n")
	fmt.Fprintf(os.Stderr, " %d consumer key(s) généré(s)\n", len(results))
	fmt.Fprintf(os.Stderr, "═══════════════════════════════════════════════════════════════\n")
	fmt.Fprintln(os.Stderr, " IMPORTANT: chaque consumer key doit être VALIDÉ par toi en")
	fmt.Fprintln(os.Stderr, " ouvrant la validation_url correspondante dans un navigateur")
	fmt.Fprintln(os.Stderr, " logué sur ton compte OVH. Tant que ce n'est pas fait, le")
	fmt.Fprintln(os.Stderr, " consumer key est en état 'pendingValidation'.")
	fmt.Fprintln(os.Stderr, "═══════════════════════════════════════════════════════════════")
}
