local ACF       = ACF
local Types     = ACF.Classes.ArmorTypes

-- Name       : full display name
-- ShortName  : abbreviated display name, used where space is limited (e.g. the cost comparison grid)
-- Density stored in kg/m^3
-- CostMul    : points per m^3
-- HealthMul  : health pool per unit volume
-- KineticMul : RHA equivalent multiplier vs kinetic (AP) threats
-- ChemicalMul: RHA equivalent multiplier vs chemical energy (HEAT/shaped charge) threats
-- SpallMul   : multiplier on spall fragment mass produced when this material is penetrated
-- Hardness   : indentation hardness relative to RHA, faces harder than RHA erode kinetic penetrators
-- Toughness  : fracture toughness in MPa*m^0.5, sets spall fragment size and how well a layer backs a hard face
-- SoundSpeed : bulk sound speed in m/s, with Density it gives the acoustic impedance used for confinement and spall

-- Explosive Reactive Armor (optional, only set on reactive types):
-- IsExplosive       : marks the material as reactive; convexes detonate when penetrated with enough kinetic energy
-- ExplosiveThreshold: kinetic energy (KJ) a penetrating round must carry to set off the reactive charge
-- ExplosiveFiller   : fraction of the convex's mass that detonates as HE filler when triggered

-- Default special type. Does not set mass, but abysmal for armor usage
local Armor = Types.Register("Default")
function Armor:OnLoaded()
    self.Name        = "Default"
    self.ShortName   = "Default"
    self.Description = "Used as a default material for entities. Not intended to provide any protection."
    self.Density     = 100
    self.CostMul     = 2.21
    self.HealthMul   = 0.0127551
    self.KineticMul  = 1e-4
    self.ChemicalMul = 1e-4
    self.SpallMul    = 1e-4
    self.Hardness    = 0.01
    self.Toughness   = 1
    self.SoundSpeed  = 1000
end

-- Flesh
local Armor = Types.Register("Flesh")
function Armor:OnLoaded()
    self.Name        = "Flesh"
    self.ShortName   = "Flesh"
    self.Description = "Soft tissue, used to represent crew members. Lab-grown for your convenience."
    self.Density     = 1100 -- https://www.sciencedirect.com/topics/immunology-and-microbiology/body-density
    self.CostMul     = 5
    self.HealthMul   = 0.01
    self.KineticMul  = 0.03
    self.ChemicalMul = 0.03
    self.SpallMul    = 0.2
    self.Hardness    = 0.01
    self.Toughness   = 1
    self.SoundSpeed  = 1540
end

-- Diesel
local Armor = Types.Register("Diesel")
function Armor:OnLoaded()
    self.Name        = "Diesel"
    self.ShortName   = "Diesel"
    self.Description = "Diesel fuel, provides some protection against shaped charges. Doesn't explode, unlike petrol and Li-Ion batteries."
    self.SuppressLoad = true
    self.Density     = 745 -- lua/acf/entities/fuel_types/diesel.lua (0.745 kg/L)
    self.CostMul     = 2
    self.HealthMul   = 0.00637755
    self.KineticMul  = 0.1
    self.ChemicalMul = 0.3
    self.SpallMul    = 0.1
    self.Hardness    = 0
    self.Toughness   = 0
    self.SoundSpeed  = 1250
end

-- Petrol
local Armor = Types.Register("Petrol")
function Armor:OnLoaded()
    self.Name        = "Petrol"
    self.ShortName   = "Petrol"
    self.Description = "Petrol fuel, provides negligible protection. Prone to detonate when penetrated or damaged."
    self.SuppressLoad = true
    self.Density     = 832 -- lua/acf/entities/fuel_types/petrol.lua (0.832 kg/L)
    self.CostMul     = 2.3
    self.HealthMul   = 0.00510204
    self.KineticMul  = 0.1
    self.ChemicalMul = 0.1
    self.SpallMul    = 0.1
    self.Hardness    = 0
    self.Toughness   = 0
    self.SoundSpeed  = 1200
end

-- Li-Ion
local Armor = Types.Register("LiIon")
function Armor:OnLoaded()
    self.Name        = "Li-Ion Battery"
    self.ShortName   = "Li-Ion"
    self.Description = "Lithium-ion battery cells. Prone to detonate when penetrated or damaged."
    self.SuppressLoad = true
    self.Density     = 3890 -- lua/acf/entities/fuel_types/electric.lua (3.89 kg/L)
    self.CostMul     = 8
    self.HealthMul   = 0.00255102
    self.KineticMul  = 0.3
    self.ChemicalMul = 0.3
    self.SpallMul    = 0.5
    self.Hardness    = 0.3
    self.Toughness   = 5
    self.SoundSpeed  = 3000
end

local Armor = Types.Register("Wing")
function Armor:OnLoaded()
    self.Name        = "Aircraft Aluminum"
    self.ShortName   = "Aircraft Aluminum"
    self.Description = "For aircraft wings and similar hollow structures. Very light."
    self.Density     = 1080 -- https://en.wikipedia.org/wiki/Aluminium
    self.CostMul     = 12
    self.HealthMul   = 0.110204
    self.KineticMul  = 0.2
    self.ChemicalMul = 0.24
    self.SpallMul    = 0.2
    self.Hardness    = 0.4
    self.Toughness   = 30
    self.SoundSpeed  = 5300
    self.Color       = Color(127, 0, 95)
end


-- Aluminum
local Armor = Types.Register("Aluminum")
function Armor:OnLoaded()
    self.Name        = "Aluminum"
    self.ShortName   = "Aluminum"
    self.Description = "Decent protection for its price and density."
    self.Density     = 2700 -- https://en.wikipedia.org/wiki/Aluminium
    self.CostMul     = 52
    self.HealthMul   = 0.5
    self.KineticMul  = 0.5
    self.ChemicalMul = 0.45 -- Hydrodynamic jet limit is 0.59, less strength than steel
    self.SpallMul    = 0.5
    self.Hardness    = 0.4
    self.Toughness   = 30
    self.SoundSpeed  = 5300
    self.Color       = Color(255, 255, 255)
end

-- RHA
local Armor = Types.Register("RHA")
function Armor:OnLoaded()
    self.Name        = "RHA"
    self.ShortName   = "RHA"
    self.Description = "Rolled Homogeneous Armor. The standard by which all other armor types are measured."
    self.Density     = 7840 -- https://metalzenith.com/blogs/steel-properties/rha-steel-properties-and-key-applications-in-defense
    self.CostMul     = 54 -- Reference: 0.005 points/kg
    self.HealthMul   = 2
    self.KineticMul  = 1.0
    self.ChemicalMul = 1.0
    self.SpallMul    = 1.0
    self.Hardness    = 1
    self.Toughness   = 100
    self.SoundSpeed  = 4570
    self.Color       = Color(145, 145, 145)
end

-- HHRHA
local Armor = Types.Register("HHRHA")
function Armor:OnLoaded()
    self.Name        = "High Hardness RHA"
    self.ShortName   = "HHRHA"
    self.Description = "Harder than RHA, but more brittle. Erodes rounds best as a face over a tougher backing such as RHA."
    self.Density     = 7850 -- https://metalzenith.com/blogs/steel-properties/rha-steel-properties-and-key-applications-in-defense
    self.CostMul     = 68
    self.HealthMul   = 0.75
    self.KineticMul  = 1.15 -- Hazell Table 7.3, 550 BHN plate is 1.16x RHA alone; hard face pairing adds more
    self.ChemicalMul = 1.05 -- Jets are mostly hydrodynamic, so hardness adds little
    self.SpallMul    = 1.3
    self.Hardness    = 1.45
    self.Toughness   = 60
    self.SoundSpeed  = 4570
    self.Color       = Color(255, 137, 137)
end

-- Gun Steel
local Armor = Types.Register("GunSteel")
function Armor:OnLoaded()
    self.Name        = "Gun Steel"
    self.ShortName   = "Gun Steel"
    self.Description = "Material intended to represent guns. Much healthier than components, but worse in protection per unit volume for balance reasons."
    self.SuppressLoad = true
    self.Density     = 7840 -- https://metalzenith.com/blogs/steel-properties/rha-steel-properties-and-key-applications-in-defense
    self.CostMul     = 39.2
    self.HealthMul   = 2
    self.KineticMul  = 0.7
    self.ChemicalMul = 0.7
    self.SpallMul    = 1.0
    self.Hardness    = 1
    self.Toughness   = 100
    self.SoundSpeed  = 4570
end

-- Component Material
local Armor = Types.Register("Component")
function Armor:OnLoaded()
    self.Name        = "Component"
    self.ShortName   = "Component"
    self.Description = "Material intended to represent components. Better protection than Gun Steel, but worse health for balance reasons."
    self.SuppressLoad = true
    self.Density     = 2700 -- https://en.wikipedia.org/wiki/Aluminium
    self.CostMul     = 17.9
    self.HealthMul   = 0.03
    self.KineticMul  = 0.1
    self.ChemicalMul = 0.1
    self.SpallMul    = 1
    self.Hardness    = 0.4
    self.Toughness   = 30
    self.SoundSpeed  = 5300
end

-- Rubber
local Armor = Types.Register("Rubber")
function Armor:OnLoaded()
    self.Name        = "Rubber"
    self.ShortName   = "Rubber"
    self.Description = "Very cheap and light, but offers very little protection and does not stop spall. Confined between steel plates it bulges into jets."
    self.Density     = 1150 -- Typical vulcanized rubber, 1100-1200 kg/m^3
    self.CostMul     = 23 -- Reference: 0.02 points/kg
    self.HealthMul   = 0.7
    self.KineticMul  = 0.3 -- Hydrodynamic limit is 0.38, lower since RHA still has some strength
    self.ChemicalMul = 0.38 -- Hydrodynamic jet penetration, sqrt of the density ratio to RHA
    self.SpallMul    = 0.8 -- Behaves like a fluid at high velocity, so it is a poor spall liner
    self.Hardness    = 0.02
    self.Toughness   = 2
    self.SoundSpeed  = 1600
    self.Color       = Color(36, 36, 36)
end

-- Textolite
local Armor = Types.Register("Textolite")
function Armor:OnLoaded()
    self.Name        = "Textolite"
    self.ShortName   = "Textolite"
    self.Description = "Layered fibrous laminate material. Weak alone, but confined between steel plates it disrupts jets and rods well. Cheap and light."
    self.Density     = 1800 -- * http://www.china-anza.com/2-1-7-textolite-3025.html
    self.CostMul     = 32
    self.HealthMul   = 0.2
    self.KineticMul  = 0.4 -- Weak alone, gains when confined between stiffer plates
    self.ChemicalMul = 0.45 -- Hydrodynamic limit is 0.48, the textolite sandwich effect comes from confinement
    self.SpallMul    = 0.3
    self.Hardness    = 0.15
    self.Toughness   = 20
    self.SoundSpeed  = 2800
    self.Color       = Color(255, 191, 0)
end

-- Aramid
local Armor = Types.Register("Aramid")
function Armor:OnLoaded()
    self.Name        = "Aramid"
    self.ShortName   = "Aramid"
    self.Description = "Kevlar style aramid fiber laminate. Poor protection against large threats, but an excellent spall liner. Expensive and tears easily."
    self.Density     = 1300 -- Aramid and resin laminate, the fiber alone is 1440 kg/m^3
    self.CostMul     = 52 -- Reference: 0.04 points/kg
    self.HealthMul   = 0.35
    self.KineticMul  = 0.45
    self.ChemicalMul = 0.4
    self.SpallMul    = 0.05
    self.Hardness    = 0.1
    self.Toughness   = 50
    self.SoundSpeed  = 2500
    self.Color       = Color(95, 160, 120)
end

-- DU
local Armor = Types.Register("DU")
function Armor:OnLoaded()
    self.Name        = "Depleted Uranium"
    self.ShortName   = "DU"
    self.Description = "Expensive and dense with high protection."
    self.Density     = 19050 -- https://en.wikipedia.org/wiki/Uranium
    self.CostMul     = 157
    self.HealthMul   = 4.29336
    self.KineticMul  = 1.8
    self.ChemicalMul = 1.3
    self.SpallMul    = 1.3
    self.Hardness    = 1.2
    self.Toughness   = 40
    self.SoundSpeed  = 2490
    self.Color       = Color(140, 255, 168)
end

-- Silicon Carbide
local Armor = Types.Register("SiliconCarbide")
function Armor:OnLoaded()
    self.Name        = "Silicon Carbide"
    self.ShortName   = "SiC"
    self.Description = "Excellent protection when backed by a tougher layer, mediocre alone. Brittle, loses effectiveness as it is damaged, and expensive."
    self.Density     = 3210 -- https://en.wikipedia.org/wiki/Silicon_carbide
    self.CostMul     = 100
    self.HealthMul   = 0.05
    self.KineticMul  = 1.35 -- Unbacked, a tough backing raises this to about 2.2
    self.ChemicalMul = 1.2
    self.SpallMul    = 1.5
    self.Hardness    = 6
    self.Toughness   = 4
    self.SoundSpeed  = 8300
    self.Color       = Color(0, 44, 70)
end

-- Light ERA
local Armor = Types.Register("LightERA")
function Armor:OnLoaded()
    self.Name        = "Light ERA"
    self.ShortName   = "Light ERA"
    self.Description = "Explosive Reactive Armor. Effective primarily against shaped charges. Will explode when hit with enough energy."
    self.Density     = 5000 -- * https://below-the-turret-ring.blogspot.com/2016/04/explosive-reactive-armor-some-history.html
    self.CostMul     = 32
    self.HealthMul   = 0.23
    self.KineticMul  = 0.3
    self.ChemicalMul = 2.0
    self.PassiveMul  = 0.2
    self.SpallMul    = 0.1
    self.Hardness    = 0.8
    self.Toughness   = 30
    self.SoundSpeed  = 3000
    self.Color       = Color(255, 219, 112)

    self.IsExplosive        = true
    self.ExplosiveThreshold = 100
    self.ExplosiveFiller    = 0.01
end

-- Heavy ERA
local Armor = Types.Register("HeavyERA")
function Armor:OnLoaded()
    self.Name        = "Heavy ERA"
    self.ShortName   = "Heavy ERA"
    self.Description = "Heavy Explosive Reactive Armor. Offers better protection against kinetic threats and takes more energy to detonate than Light ERA, but is twice as dense and more expensive."
    self.Density     = 10000 -- * https://below-the-turret-ring.blogspot.com/2016/04/explosive-reactive-armor-some-history.html
    self.CostMul     = 54
    self.HealthMul   = 0.55
    self.KineticMul  = 1.33
    self.ChemicalMul = 2.0
    self.PassiveMul  = 0.5
    self.SpallMul    = 0.2
    self.Hardness    = 1
    self.Toughness   = 60
    self.SoundSpeed  = 4000
    self.Color       = Color(127, 111, 63)

    self.IsExplosive        = true
    self.ExplosiveThreshold = 200
    self.ExplosiveFiller    = 0.01
end

-- NERA
local Armor = Types.Register("NERA")
function Armor:OnLoaded()
    self.Name        = "NERA"
    self.ShortName   = "NERA"
    self.Description = "Non-Explosive Reactive Armor, steel plates around rubber interlayers like the Abrams turret cassettes. Bulges against shaped charges and long rods, but never detonates. Weaker than ERA against HEAT, in exchange for being safe and sustained."
    self.Density     = 5164 -- 60% RHA and 40% rubber by volume
    self.CostMul     = 40 -- Between the raw material cost (28) and Heavy ERA (47.1), for the cassette assembly
    self.HealthMul   = 0.8
    self.KineticMul  = 0.75 -- Just above the linear steel and rubber mix (0.72), the bulging plates disrupt rods a little
    self.ChemicalMul = 1.0 -- Slightly above a hand built steel/rubber/steel sandwich (~0.93), for the engineered cassette
    self.SpallMul    = 0.7 -- Steel plates still spall, but the rubber layers soak up some
    self.Hardness    = 0.8
    self.Toughness   = 60
    self.SoundSpeed  = 3000
    self.Color       = Color(110, 125, 140)
end

-- Reinforced Concrete
local Armor = Types.Register("ReinforcedConcrete")
function Armor:OnLoaded()
    self.Name        = "Reinforced Concrete"
    self.ShortName   = "Reinforced Concrete"
    self.Description = "Cheap and weak protection per unit volume compared to RHA, but low enough cost to make up for it in large stationary structures."
    self.Density     = 2500 -- https://www.civilengicon.com/2024/02/density-of-rcc-pcc-sand-cement.html
    self.CostMul     = 6.5
    self.HealthMul   = 0.2
    self.KineticMul  = 0.22
    self.ChemicalMul = 0.3
    self.SpallMul    = 1.6
    self.Hardness    = 0.3
    self.Toughness   = 1
    self.SoundSpeed  = 3500
    self.Color       = Color(70, 70, 70)
end

-- Wood
local Armor = Types.Register("Wood")
function Armor:OnLoaded()
    self.Name        = "Wood"
    self.ShortName   = "Wood"
    self.Description = "The cheapest and lightest material available. Offers almost no meaningful protection against anything, but its low cost and low density make it usable for early aircraft, or non-combat use as scaffolds and housing."
    self.Density     = 900 -- https://www.engineeringtoolbox.com/wood-density-d_40.html specifically oak.
    self.CostMul     = 4
    self.HealthMul   = 0.08
    self.KineticMul  = 0.06
    self.ChemicalMul = 0.07
    self.SpallMul    = 0.75
    self.Hardness    = 0.05
    self.Toughness   = 8
    self.SoundSpeed  = 2000
    self.Color       = Color(133, 94, 66)
end