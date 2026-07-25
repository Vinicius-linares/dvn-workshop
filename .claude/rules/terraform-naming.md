---
name: "terraform-naming"
description: "Convenções de nomenclatura, layout de arquivos e modelagem de variables para código Terraform. Aplica-se a todo arquivo .tf: nomes de resources, data sources, variables, outputs, modules, locals, organização física dos arquivos e estrutura das variáveis (sem hard-coding, variáveis contextualizadas). Baseado em terraform-best-practices.com/naming."
applies_to:
  - "**/*.tf"
  - "**/*.tfvars"
---

# Regra: Nomenclatura em Terraform

Toda escrita ou revisão de código Terraform **deve** seguir estas convenções.
Referência canônica: https://www.terraform-best-practices.com/naming

## 1. Convenções gerais

- Use `_` (underscore) em vez de `-` (dash) em **todos** os nomes do Terraform:
  nomes de resources, data sources, variables, outputs, modules e locals.
- Prefira letras minúsculas e números (mesmo que UTF-8 seja suportado).
- Estas regras valem para os **nomes do Terraform**. Restrições próprias dos
  recursos de nuvem (ex.: nome de bucket S3, nome de DNS) são tratadas nos
  **valores** dos argumentos, não nos nomes dos blocos.

## 2. Resources e data sources

- **Não repita o tipo do recurso** no nome do bloco (nem parcial nem totalmente):
  - ✅ `resource "aws_route_table" "public" {}`
  - ❌ `resource "aws_route_table" "public_route_table" {}`
  - ❌ `resource "aws_route_table" "public_aws_route_table" {}`
- Use `this` como nome quando não houver um nome mais descritivo, ou quando o
  módulo cria um único recurso daquele tipo.
- **Sempre use substantivos no singular** para os nomes.
- Use `-` (dash) **dentro de valores de argumentos** e em qualquer lugar onde o
  valor será exposto a um humano (ex.: dentro do nome DNS de uma instância RDS).
- Inclua o argumento `count` / `for_each` como o **primeiro** argumento do bloco,
  no topo, separado por uma linha em branco do restante.
- Ao usar condição em `count` / `for_each`, prefira valores **booleanos** em vez
  de `length` ou outras expressões.
- Inclua `tags` (quando suportado) como o **último** argumento real, seguido por
  `depends_on` e `lifecycle`, se necessário.

## 3. Variables

- Não reinvente a roda em módulos de recurso: use `name`, `description` e
  `default` conforme definidos na seção "Argument Reference" do provider.
- Use a **forma plural** no nome quando o tipo for `list(...)` ou `map(...)`.
- Ordene as chaves de um bloco `variable` nesta sequência:
  `description`, `type`, `default`, `validation`.
- **Sempre** inclua `description` em todas as variables, mesmo que pareça óbvio.
- Prefira tipos simples (`number`, `string`, `list(...)`, `map(...)`, `any`)
  em vez de tipos específicos como `object()`.
- Use tipos específicos como `map(map(string))` se todos os elementos do mapa
  tiverem o mesmo tipo.
- Use o tipo `any` para desabilitar validação de tipo a partir de certa
  profundidade ou quando múltiplos tipos precisam ser suportados.
- Use `tomap(...)` para distinguir mapas de objetos, já que `{}` é ambíguo.
- **Evite negativas duplas**: use nomes positivos para prevenir confusão.
- Para variables que nunca devem ser `null`, defina `nullable = false`.

## 4. Outputs

- Torne os outputs consistentes e compreensíveis fora do seu escopo.
- Estrutura do nome do output: `{name}_{type}_{attribute}`
  - `{name}` — identifica o recurso ou fonte de dados
  - `{type}` — o tipo do recurso **sem** o prefixo do provider
  - `{attribute}` — o atributo retornado
- Se o output retorna um valor com funções de interpolação e múltiplos recursos,
  `{name}` e `{type}` devem ser o mais genéricos possível.
- Se o valor retornado é uma lista, o nome deve estar no **plural**.
- **Sempre** inclua `description` em todos os outputs, mesmo que pareça óbvio.
- Evite definir `sensitive` a menos que você controle totalmente o uso do output
  em todos os lugares.
- Prefira `try()` (disponível desde o Terraform 0.13) em vez de
  `element(concat(...))`.

## 5. Layout de arquivos

Separe os recursos em **arquivos por componente**, usando um prefixo de domínio
seguido de sufixos descritivos em kebab-case, separados por ponto (`.`). Um
recurso (ou grupo coeso de recursos do mesmo propósito) por arquivo.

**Padrão:** `<dominio>.<componente>.tf`

- O `<dominio>` agrupa recursos relacionados (ex.: `vpc`).
- O `<componente>` descreve o recurso específico daquele arquivo, em kebab-case.
- O arquivo raiz do domínio, sem sufixo (ex.: `vpc.tf`), contém o recurso
  central daquele domínio.

**Exemplo para uma VPC:**

```
vpc.tf                        # a VPC em si (aws_vpc)
vpc.public-subnets.tf         # subnets públicas
vpc.private-subnets.tf        # subnets privadas
vpc.public-route-table.tf     # route table pública + associações
vpc.private-route-table.tf    # route table privada + associações
vpc.internet-gateway.tf       # internet gateway
vpc.nat-gateway.tf            # NAT gateway + EIP
```

Regras:

- Use **sempre** este padrão ao criar novos recursos — não concentre tudo em um
  único `main.tf`.
- O prefixo `<dominio>` (ex.: `vpc`) deve ser consistente entre todos os arquivos
  do mesmo domínio.
- Nos **nomes de arquivos** use `-` (dash) para separar palavras dentro de um
  segmento (ex.: `public-route-table`); isto é uma exceção intencional à regra do
  `_` da seção 1, que se aplica aos **nomes internos do Terraform**, não aos
  nomes de arquivos.
- `variables.tf`, `outputs.tf`, `versions.tf`/`providers.tf` permanecem como
  arquivos convencionais na raiz do módulo.

## 6. Modelagem de variables (sem hard-coding, contextualizadas)

Estas regras têm **prioridade** sobre a preferência por tipos simples da Seção 3
quando houver conflito: aqui privilegiamos **contexto e coesão** dos dados.

- **Nunca** use valores hard-coded (strings, CIDRs, nomes, números, AZs, flags)
  diretamente nos blocos de `resource`/`data`. Todo valor configurável deve vir
  de uma `variable` (ou de `locals` derivados de variables).
- Prefira **variáveis contextualizadas e agrupadas** a variáveis isoladas soltas.
  Modele o dado como um **objeto com atributos** que carrega o contexto junto,
  em vez de espalhar vários escalares independentes.
- Quando houver uma coleção de itens do mesmo tipo (ex.: subnets), use uma
  **lista de objetos**, onde cada item traz todos os seus atributos (cidr, nome,
  AZ, etc.), e itere com `for_each`/`count`.

### Exemplo — ✅ contextualizado vs. ❌ isolado

❌ **Evite** — variáveis isoladas e desconexas:

```hcl
variable "public_subnet_cidr_a"  { type = string }
variable "public_subnet_cidr_b"  { type = string }
variable "private_subnet_cidr_a" { type = string }
variable "private_subnet_cidr_b" { type = string }
variable "vpc_cidr"              { type = string }
```

✅ **Prefira** — uma variável `vpc` que carrega o contexto e listas de objetos
por tipo de subnet, cada item com seus próprios atributos:

```hcl
variable "vpc" {
  description = "Definição da VPC e suas subnets, com atributos por subnet."
  type = object({
    name = string
    cidr = string
    public_subnets = list(object({
      name              = string
      cidr              = string
      availability_zone = string
    }))
    private_subnets = list(object({
      name              = string
      cidr              = string
      availability_zone = string
    }))
  })
}
```

Consumo com `for_each`, sem nenhum valor hard-coded no resource:

```hcl
resource "aws_subnet" "public" {
  for_each = { for s in var.vpc.public_subnets : s.name => s }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone

  tags = { Name = each.value.name }
}
```

- Os valores concretos moram em `*.tfvars` (ou defaults da variável), **nunca**
  inline no resource.
- Ainda valem as demais regras da Seção 3 (sempre `description`; use plural para
  os atributos que são listas — ex.: `public_subnets`; ordene as chaves do bloco
  `variable`). O uso de `object(...)` aqui é a exceção justificada à preferência
  por tipos simples, porque o ganho de contexto e coesão compensa.
